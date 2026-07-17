import AVFoundation
import Foundation

/// Innertube android_vr source: fetches adaptive DASH formats and plays them as
/// a SIDX-generated HLS stream (with native-HLS / progressive fallbacks). Owns
/// quality selection from the DASH ladder.
final class AndroidVRSource: VideoSource {
    private static let noStreamError = NSError(
        domain: "AndroidVRSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No playable stream"]
    )

    let kind: VideoSourceKind = .androidVR
    var supportsQualitySelection: Bool { !availableQualities.isEmpty }
    private(set) var availableQualities: [VideoQuality] = []
    private(set) var currentQuality: VideoQuality?

    private let apiClient: WatchService
    private let liveHLS: LiveHLSPlayback
    private let client: DirectPlaybackClient = .androidVR
    private var info: DirectPlaybackInfo?

    init(apiClient: WatchService, resolver: HLSStreamResolver = .shared) {
        self.apiClient = apiClient
        liveHLS = LiveHLSPlayback(resolver: resolver)
    }

    static func qualities(from info: DirectPlaybackInfo) -> [VideoQuality] {
        info.allDashVideoFormats.map { format in
            let fps = format.fps ?? 0
            let height = format.height ?? 0
            // YouTube's tier name when present — non-16:9 heights are
            // off-ladder (1920x1012 is the "1080p" tier, not "1012p").
            let fallback = fps > 30 ? "\(height)p\(fps)" : "\(height)p"
            return VideoQuality(
                id: "\(format.itag)",
                label: format.qualityLabel ?? fallback,
                height: format.height,
                fps: format.fps
            )
        }
        .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: nil,
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
        buildGeneratedHLS(
            info: info, video: format, audio: audio, completion: completion
        )
    }

    // MARK: - Private

    private func handleInfo(
        _ info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        self.info = info
        liveHLS.reset()
        availableQualities = Self.qualities(from: info)
        currentQuality = info.dashVideoFormat.flatMap { selected in
            availableQualities.first { $0.id == "\(selected.itag)" }
        }
        buildBest(info: info, completion: completion)
    }

    private func buildBest(
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if let video = info.dashVideoFormat, let audio = info.dashAudioFormat {
            buildGeneratedHLS(
                info: info, video: video, audio: audio, completion: completion
            )
        } else if let hls = info.hlsManifestURL {
            loadLiveHLS(info: info, url: hls, completion: completion)
        } else if let progressive = info.progressiveURL {
            let item = progressiveItem(progressive, info: info)
            completion(.success(prepared(item: item, info: info)))
        } else {
            completion(.failure(Self.noStreamError))
        }
    }

    private func buildGeneratedHLS(
        info: DirectPlaybackInfo,
        video: DashFormatInfo,
        audio: DashFormatInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let input = HLSPlaybackBuilder.BuildInput(
            videoURL: client.directURL(baseURL: video.url, poToken: nil),
            audioURL: client.directURL(baseURL: audio.url, poToken: nil),
            videoFormat: video,
            audioFormat: audio,
            headers: client.streamHeaders(visitorData: info.visitorData)
        )
        HLSPlaybackBuilder.build(input: input) { result in
            guard let result else {
                completion(.failure(Self.noStreamError))
                return
            }
            completion(.success(
                PreparedPlayback(
                    item: result.playerItem,
                    resourceLoader: result.loader,
                    captions: info.captionTracks,
                    duration: info.duration
                )
            ))
        }
    }

    private func progressiveItem(
        _ url: URL, info: DirectPlaybackInfo
    ) -> AVPlayerItem {
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let asset = AVURLAsset(
            url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return AVPlayerItem(asset: asset)
    }

    private func prepared(
        item: AVPlayerItem, info: DirectPlaybackInfo
    ) -> PreparedPlayback {
        PreparedPlayback(
            item: item, captions: info.captionTracks, duration: info.duration
        )
    }
}

// MARK: - Live HLS

private extension AndroidVRSource {
    /// Live streams (no DASH SIDX ladder): [[LiveHLSPlayback]] exposes the
    /// multivariant playlist's variants as qualities and starts on Auto. A
    /// failed playlist fetch degrades to direct playback with no picker.
    func loadLiveHLS(
        info: DirectPlaybackInfo,
        url: URL,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        liveHLS.load(url: url, info: info) { [weak self] prepared in
            guard let self else {
                return
            }
            if !liveHLS.qualities.isEmpty {
                availableQualities = liveHLS.qualities
                currentQuality = liveHLS.startQuality
            }
            completion(.success(prepared))
        }
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
