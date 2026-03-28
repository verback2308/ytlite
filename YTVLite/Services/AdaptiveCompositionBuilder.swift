import AVFoundation

/// Builds an AVMutableComposition from separate video and audio URLs.
enum AdaptiveCompositionBuilder {
    /// Loads video and audio assets, composes them, and returns the resulting AVPlayerItem.
    /// Calls completion on the main queue.
    static func build(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        completion: @escaping (AVPlayerItem?) -> Void
    ) {
        let startTime = CACurrentMediaTime()
        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let videoAsset = AVURLAsset(url: videoURL, options: assetOptions)
        let audioAsset = AVURLAsset(url: audioURL, options: assetOptions)

        loadAssets(video: videoAsset, audio: audioAsset) { loadError in
            let elapsed = CACurrentMediaTime() - startTime
            guard !loadError else {
                AppLog.player(String(format: "metadata failed (%.1fs)", elapsed))
                completion(nil)
                return
            }

            let item = compose(videoAsset: videoAsset, audioAsset: audioAsset)
            if let item {
                PlaybackBufferPolicy.configure(item: item)
                AppLog.player(String(format: "ready (%.1fs)", elapsed))
            }
            completion(item)
        }
    }

    private static func loadAssets(
        video: AVURLAsset,
        audio: AVURLAsset,
        completion: @escaping (Bool) -> Void
    ) {
        let group = DispatchGroup()
        var loadError = false

        group.enter()
        video.loadValuesAsynchronously(forKeys: ["tracks"]) {
            if !checkAssetStatus(video, key: "tracks", label: "video") {
                loadError = true
            }
            group.leave()
        }

        group.enter()
        audio.loadValuesAsynchronously(forKeys: ["tracks"]) {
            if !checkAssetStatus(audio, key: "tracks", label: "audio") {
                loadError = true
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(loadError)
        }
    }

    private static func checkAssetStatus(
        _ asset: AVURLAsset,
        key: String,
        label: String
    ) -> Bool {
        var error: NSError?
        let status = asset.statusOfValue(forKey: key, error: &error)
        if status != .loaded {
            AppLog.player(
                "\(label) tracks failed: "
                    + "\(error?.localizedDescription ?? "unknown")"
            )
            return false
        }
        return true
    }

    private static func compose(
        videoAsset: AVURLAsset,
        audioAsset: AVURLAsset
    ) -> AVPlayerItem? {
        guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first,
              let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first
        else {
            AppLog.player("no video/audio tracks found")
            return nil
        }

        let composition = AVMutableComposition()
        guard let tracks = addCompositionTracks(composition) else {
            return nil
        }

        return insertTracks(
            composition: composition,
            videoTrack: tracks.video,
            audioTrack: tracks.audio,
            sourceVideo: sourceVideoTrack,
            sourceAudio: sourceAudioTrack,
            videoAsset: videoAsset,
            audioAsset: audioAsset
        )
    }

    private static func addCompositionTracks(
        _ composition: AVMutableComposition
    ) -> (video: AVMutableCompositionTrack, audio: AVMutableCompositionTrack)? {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
              let audioTrack = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else {
            return nil
        }
        return (videoTrack, audioTrack)
    }

    private static func insertTracks( // swiftlint:disable:this function_parameter_count
        composition: AVMutableComposition,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack,
        sourceVideo: AVAssetTrack,
        sourceAudio: AVAssetTrack,
        videoAsset: AVURLAsset,
        audioAsset: AVURLAsset
    ) -> AVPlayerItem? {
        let duration = CMTimeMinimum(
            videoAsset.duration, audioAsset.duration
        )
        let range = CMTimeRange(start: .zero, duration: duration)
        do {
            try videoTrack.insertTimeRange(
                range, of: sourceVideo, at: .zero
            )
            try audioTrack.insertTimeRange(
                range, of: sourceAudio, at: .zero
            )
            videoTrack.preferredTransform = sourceVideo.preferredTransform
        } catch {
            AppLog.player("composition failed: \(error)")
            return nil
        }

        return AVPlayerItem(asset: composition)
    }
}
