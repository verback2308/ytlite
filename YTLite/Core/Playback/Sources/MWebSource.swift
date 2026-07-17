import AVFoundation
import Foundation

/// Anonymous mobile-web (MWEB) source for kids / dubbed content. Its adaptive
/// URLs carry `rqh=1` (need a GVS `pot`) and an unsolved `n` throttling param.
/// The `pot` is minted by [[RemotePoTokenService]] bound to the VIDEO ID
/// (YouTube's current mweb experiment binds it to the video, not visitorData);
/// `n` is solved via [[HLSStreamResolver]] (on-device on iOS 14+, remote on
/// 12/13). Plays the DASH ladder as SIDX-generated HLS. Covers regular + dubbed
/// (kids arrive signature-ciphered, handled separately).
final class MWebSource: VideoSource {
    static let noStreamError = NSError(
        domain: "MWebSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No playable stream"]
    )
    /// Player-JS path is global per session — solving `n` needs it, so cache it
    /// across videos instead of re-scraping the watch page each time.
    static var cachedJsPath: String?
    /// signatureTimestamp scraped from the SAME watch page as `cachedJsPath`.
    /// The /player STS claim and the n-solve player must stay consistent —
    /// after a player rotation a mismatched pair gets every range 403'd.
    static var cachedSTS: Int?

    let kind: VideoSourceKind = .mwebPot
    var supportsQualitySelection: Bool { !availableQualities.isEmpty }
    var currentCodecs: String? {
        AndroidVRSource.codecsLine(info: info, quality: currentQuality)
    }
    private(set) var availableQualities: [VideoQuality] = []
    private(set) var currentQuality: VideoQuality?

    let apiClient: WatchService
    let poTokenService: PoTokenProvider
    let resolver: HLSStreamResolver
    let liveHLS: LiveHLSPlayback
    let client: DirectPlaybackClient = .mweb
    var info: DirectPlaybackInfo?
    var poToken: String?
    var visitorData: String?
    /// Remembered for the deferred pot mint when playback starts from a
    /// quality pick after a [[probeQualities]] (no pot minted at probe time).
    var currentVideoId: String?
    /// One-shot guard for the fresh-pot /player retry.
    var didRetryFreshPot = false
    /// Balances the async pot mint: the pot is only needed as a media-URL
    /// param, so it's minted in parallel with /player + n-solving and the
    /// build step waits on this group.
    let potWait = DispatchGroup()

    init(
        apiClient: WatchService,
        poTokenService: PoTokenProvider = RemotePoTokenService.shared,
        resolver: HLSStreamResolver = .shared
    ) {
        self.apiClient = apiClient
        self.poTokenService = poTokenService
        self.resolver = resolver
        liveHLS = LiveHLSPlayback(resolver: resolver)
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        currentVideoId = videoId
        mintPot(videoId: videoId)
        resolvePlayerContext(videoId: videoId) { [weak self] in
            guard let self, cancellation?.isCancelled != true else {
                return
            }
            self.fetchPlayback(
                videoId: videoId,
                cancellation: cancellation,
                completion: completion
            )
        }
    }

    func selectQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if liveHLS.isActive {
            selectLiveQuality(quality, completion: completion)
            return
        }
        guard let info,
              let format = info.allDashVideoFormats.first(
                  where: { "\($0.itag)" == quality.id }
              ),
              let audio = info.dashAudioFormat else {
            completion(.failure(Self.noStreamError))
            return
        }
        currentQuality = quality
        // Probe path never minted a pot; without one every range 403s (rqh=1).
        if poToken == nil, let videoId = currentVideoId {
            mintPot(videoId: videoId)
        }
        solveThenBuild(info: info, video: format, audio: audio, completion: completion)
    }

    func updateQualityState(from info: DirectPlaybackInfo) {
        self.info = info
        liveHLS.reset()
        availableQualities = AndroidVRSource.qualities(from: info)
        currentQuality = info.dashVideoFormat.flatMap { selected in
            availableQualities.first { $0.id == "\(selected.itag)" }
        }
    }

    /// `private(set)` keeps the quality setters in this file — the live
    /// extension (MWebSource+Live) publishes its state through here.
    func applyLiveQualityState() {
        availableQualities = liveHLS.qualities
        currentQuality = liveHLS.startQuality
    }

    func selectLiveQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let info,
              let prepared = liveHLS.prepared(for: quality, info: info) else {
            completion(.failure(Self.noStreamError))
            return
        }
        currentQuality = quality
        completion(.success(prepared))
    }
}

// MARK: - n-solving

extension MWebSource {
    /// Scrapes the watch page once per session for the player context pair —
    /// the base.js path (n-solving) and its `"STS"` signatureTimestamp (the
    /// /player claim). Extracted from the SAME HTML so they can never diverge
    /// across a player rotation.
    func resolvePlayerContext(videoId: String, completion: @escaping () -> Void) {
        if Self.cachedJsPath != nil, Self.cachedSTS != nil {
            completion()
            return
        }
        guard let watch = URL(
            string: "https://www.youtube.com/watch?v=\(videoId)"
        ) else {
            completion()
            return
        }
        resolver.fetchText(url: watch) { result in
            if case let .success(html) = result {
                let match = HLSStreamResolver.firstMatch(
                    in: html, pattern: "\"jsUrl\":\"([^\"]+base\\.js)\""
                )
                Self.cachedJsPath = match?.replacingOccurrences(of: "\\/", with: "/")
                let sts = HLSStreamResolver.firstMatch(in: html, pattern: "\"STS\":(\\d+)")
                Self.cachedSTS = sts.flatMap(Int.init)
            }
            AppLog.player(
                "mwebSource: jsPath=\(Self.cachedJsPath ?? "nil")"
                    + " sts=\(Self.cachedSTS.map(String.init) ?? "nil")"
            )
            completion()
        }
    }

    /// Solves each DISTINCT challenge once — `n` for both URLs plus, on
    /// ciphered (kids) formats, the `signatureCipher` `s` — then waits for
    /// the parallel pot mint before building.
    func solveThenBuild(
        info: DirectPlaybackInfo,
        video: DashFormatInfo,
        audio: DashFormatInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let group = DispatchGroup()
        let solutions = SolutionBox()
        for unsolved in Set([video.url, audio.url].compactMap(Self.nValue)) {
            group.enter()
            resolver.solveN(unsolved: unsolved, jsPath: Self.cachedJsPath) { result in
                AppLog.player("mwebSource: n \(unsolved) -> \(result ?? "FAILED(nil)")")
                solutions.store(kind: .nThrottle, unsolved: unsolved, solved: result)
                group.leave()
            }
        }
        for challenge in Set([video, audio].compactMap { $0.sigChallenge }) {
            group.enter()
            resolver.solveSig(unsolved: challenge, jsPath: Self.cachedJsPath) { result in
                AppLog.player(
                    "mwebSource: sig \(result == nil ? "FAILED" : "solved")"
                )
                solutions.store(kind: .sig, unsolved: challenge, solved: result)
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.finishBuild(
                info: info,
                streams: Self.makeStreams(video: video, audio: audio, solutions: solutions),
                completion: completion
            )
        }
    }

    /// Builds once the pot mint lands. `streams` is nil when a sig challenge
    /// stayed unsolved — that format is unplayable (every range 403s).
    func finishBuild(
        info: DirectPlaybackInfo,
        streams: SolvedStreams?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let streams else {
            completion(.failure(Self.noStreamError))
            return
        }
        potWait.notify(queue: .main) { [weak self] in
            self?.buildGeneratedHLS(info: info, streams: streams, completion: completion)
        }
    }
}
