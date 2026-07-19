import Foundation

// MARK: - Auto-dub race
//
// The dub probe runs in parallel with the primary load. Whoever finishes
// first decides how the preferred dub (AutoDubPreference) starts: probe
// first → the load commits straight to the fallback on the dubbed track and
// the primary result is discarded; primary first → the shell performs a
// visible switch when the probe lands. All handlers run on main.

extension AutoVideoSource {
    func handlePrimaryResult(
        _ result: Result<PreparedPlayback, Error>,
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        primaryOutcome = result
        if committedToDub {
            guard dubStartFailed else {
                AppLog.player(
                    "auto: \(primary.kind) result discarded (dub committed)"
                )
                return
            }
            deliverAfterDubFailure(completion: completion)
            return
        }
        switch result {
        case .success:
            completion(result)
        case .failure(let error):
            guard cancellation?.isCancelled != true else {
                completion(result)
                return
            }
            AppLog.player(
                "auto: \(primary.kind) failed (\(error)), falling back"
            )
            loadFallback(
                videoId: videoId,
                cancellation: cancellation,
                completion: completion
            )
        }
    }

    /// Metadata-only probe (no pot mint), started in parallel with the
    /// primary load so a wanted dub can start without the primary at all.
    func probeAudioTracksEarly(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard cancellation?.isCancelled != true else {
            return
        }
        let source = fallback ?? makeFallbackShared()
        source.probeAudioTracks(videoId: videoId) { [weak self] tracks in
            guard let self, !tracks.isEmpty,
                  cancellation?.isCancelled != true else {
                return
            }
            AppLog.player("auto: probe found \(tracks.count) audio tracks")
            self.handleProbedTracks(tracks, completion: completion)
        }
    }

    // MARK: - Private

    /// Probe landed (main thread). Three timings: primary already failed →
    /// the loading fallback applies the auto-dub preference in its own
    /// build; primary still loading + dub wanted → commit to the fallback;
    /// primary already playing → the shell runs the visible switch.
    private func handleProbedTracks(
        _ tracks: [AudioTrack],
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if case .failure? = primaryOutcome {
            return
        }
        guard primaryOutcome == nil else {
            NotificationCenter.default.post(
                name: .sourceAudioTracksDidChange, object: self
            )
            return
        }
        guard let target = AutoDubPreference.autoDubTrack(in: tracks),
              let fallback else {
            return
        }
        committedToDub = true
        AppLog.player("auto: starting on \(fallback.kind) dub \(target.id)")
        fallback.selectAudioTrack(target) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleDubResult(result, completion: completion)
            }
        }
    }

    private func handleDubResult(
        _ result: Result<PreparedPlayback, Error>,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        switch result {
        case .success:
            if let fallback {
                active = fallback
            }
            completion(result)
        case .failure(let error):
            AppLog.player("auto: dub start failed (\(error))")
            dubStartFailed = true
            // No-op while the primary is still in flight — its handler
            // delivers once it lands.
            deliverAfterDubFailure(completion: completion)
        }
    }

    /// Dub start failed: deliver the primary result (original audio beats no
    /// playback); a primary failure surfaces as the load error.
    private func deliverAfterDubFailure(
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let primaryOutcome else {
            return
        }
        if case .success = primaryOutcome {
            AppLog.player("auto: playing \(primary.kind) original instead")
        }
        completion(primaryOutcome)
    }
}
