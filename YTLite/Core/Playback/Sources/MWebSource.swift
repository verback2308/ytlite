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
    private(set) var availableQualities: [VideoQuality] = []
    private(set) var currentQuality: VideoQuality?

    let apiClient: WatchService
    let poTokenService: PoTokenProvider
    let resolver: HLSStreamResolver
    let client: DirectPlaybackClient = .mweb
    var info: DirectPlaybackInfo?
    var poToken: String?
    var visitorData: String?
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
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
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
        guard let info,
              let format = info.allDashVideoFormats.first(
                  where: { "\($0.itag)" == quality.id }
              ),
              let audio = info.dashAudioFormat else {
            completion(.failure(Self.noStreamError))
            return
        }
        currentQuality = quality
        solveThenBuild(info: info, video: format, audio: audio, completion: completion)
    }

    func updateQualityState(from info: DirectPlaybackInfo) {
        self.info = info
        availableQualities = AndroidVRSource.qualities(from: info)
        currentQuality = info.dashVideoFormat.flatMap { selected in
            availableQualities.first { $0.id == "\(selected.itag)" }
        }
    }
}

// MARK: - Fetch

private extension MWebSource {
    /// Mints the GVS pot bound to the VIDEO ID — YouTube's current experiment
    /// binds the mweb pot to the video id, not visitorData (verified against
    /// yt-dlp + BgUtils). Runs concurrently with /player + n-solving; the
    /// build step waits on `potWait` before injecting the pot into the URLs.
    func mintPot(videoId: String) {
        potWait.enter()
        poTokenService.fetchSessionToken(identifier: videoId) { [weak self] result in
            switch result {
            case .success(let token):
                AppLog.player("mwebSource: minted pot for videoId (\(token.prefix(12))…)")
                self?.poToken = token
            case .failure(let error):
                AppLog.player("mwebSource: pot mint failed: \(error)")
                self?.poToken = nil
            }
            self?.potWait.leave()
        }
    }

    func fetchPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        apiClient.fetchMWebPlayback(
            videoId: videoId,
            poToken: poToken,
            visitorData: visitorData,
            signatureTimestamp: Self.cachedSTS,
            cancellationToken: cancellation
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let info):
                self?.handleInfo(info, completion: completion)
            }
        }
    }

    func handleInfo(
        _ info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        updateQualityState(from: info)
        AppLog.player(
            "mwebSource: reqVD=\((visitorData ?? "nil").prefix(24))"
                + " respVD=\((info.visitorData ?? "nil").prefix(24))"
        )
        guard let video = info.dashVideoFormat,
              let audio = info.dashAudioFormat else {
            completion(.failure(Self.noStreamError))
            return
        }
        solveThenBuild(info: info, video: video, audio: audio, completion: completion)
    }
}

// MARK: - n-solving

private extension MWebSource {
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

    /// Solves each DISTINCT `n` once (video and audio typically share the
    /// value — one remote round-trip instead of two), then waits for the
    /// parallel pot mint before building.
    func solveThenBuild(
        info: DirectPlaybackInfo,
        video: DashFormatInfo,
        audio: DashFormatInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let group = DispatchGroup()
        var solved = SolvedStreams(
            video: video, audio: audio, videoURL: video.url, audioURL: audio.url
        )
        for unsolved in Set([video.url, audio.url].compactMap(Self.nValue)) {
            group.enter()
            resolver.solveN(unsolved: unsolved, jsPath: Self.cachedJsPath) { result in
                AppLog.player("mwebSource: n \(unsolved) -> \(result ?? "FAILED(nil)")")
                if let result {
                    if Self.nValue(of: video.url) == unsolved {
                        solved.videoURL = Self.replacingN(in: video.url, solved: result)
                    }
                    if Self.nValue(of: audio.url) == unsolved {
                        solved.audioURL = Self.replacingN(in: audio.url, solved: result)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.potWait.notify(queue: .main) { [weak self] in
                self?.buildGeneratedHLS(info: info, streams: solved, completion: completion)
            }
        }
    }
}
