import AVFoundation

/// Builds HLS playlists from DASH adaptive format info.
enum HLSPlaybackBuilder {
    struct Result {
        let playerItem: AVPlayerItem
        let loader: HLSPlaylistLoader
    }

    struct BuildInput {
        let videoURL: URL
        let audioURL: URL
        let videoFormat: DashFormatInfo
        let audioFormat: DashFormatInfo
        let headers: [String: String]
    }

    struct RangeRequest {
        let url: URL
        let start: Int64
        let end: Int64
        let headers: [String: String]
    }

    // MARK: - Public API

    /// Fetches SIDX data, generates HLS playlists, and
    /// returns a ready-to-play AVPlayerItem.
    static func build(
        input: BuildInput,
        completion: @escaping (Result?) -> Void
    ) {
        let startTime = CACurrentMediaTime()
        fetchSidxPair(input: input) { videoData, audioData in
            let result = processSidxData(
                input: input,
                videoData: videoData,
                audioData: audioData,
                startTime: startTime
            )
            completion(result)
        }
    }

    /// Fetch a byte range from a URL with custom headers.
    static func fetchRangeData(
        request: RangeRequest,
        completion: @escaping (Data?) -> Void
    ) {
        var urlReq = URLRequest(url: request.url)
        for (headerKey, headerVal) in request.headers {
            urlReq.setValue(
                headerVal,
                forHTTPHeaderField: headerKey
            )
        }
        let rv = "bytes=\(request.start)-\(request.end)"
        urlReq.setValue(
            rv,
            forHTTPHeaderField: HTTPHeader.range
        )
        let task = URLSession.shared.dataTask(
            with: urlReq
        ) { data, response, error in
            if let error {
                let msg = error.localizedDescription
                AppLog.hls("range fetch failed: \(msg)")
                completion(nil)
                return
            }
            let code = (response as? HTTPURLResponse)?
                .statusCode ?? 0
            if code != 206, code != 200 {
                AppLog.hls("range fetch status \(code)")
            }
            completion(data)
        }
        task.resume()
    }
}

// MARK: - Private Helpers

private extension HLSPlaybackBuilder {
    static func fetchSidxPair(
        input: BuildInput,
        completion: @escaping (Data?, Data?) -> Void
    ) {
        let group = DispatchGroup()
        var videoData: Data?
        var audioData: Data?
        group.enter()
        fetchSidxData(
            url: input.videoURL,
            format: input.videoFormat,
            headers: input.headers
        ) { data in
            videoData = data
            group.leave()
        }
        group.enter()
        fetchSidxData(
            url: input.audioURL,
            format: input.audioFormat,
            headers: input.headers
        ) { data in
            audioData = data
            group.leave()
        }
        let queue = DispatchQueue.global(qos: .userInitiated)
        group.notify(queue: queue) {
            completion(videoData, audioData)
        }
    }

    static func fetchSidxData(
        url: URL,
        format: DashFormatInfo,
        headers: [String: String],
        completion: @escaping (Data?) -> Void
    ) {
        let req = RangeRequest(
            url: url,
            start: Int64(format.indexRangeStart),
            end: Int64(format.indexRangeEnd),
            headers: headers
        )
        fetchRangeData(request: req, completion: completion)
    }

    static func processSidxData(
        input: BuildInput,
        videoData: Data?,
        audioData: Data?,
        startTime: CFTimeInterval
    ) -> Result? {
        guard let vData = videoData,
              let aData = audioData else {
            AppLog.hls("failed to fetch sidx data")
            return nil
        }
        guard let parsed = parseSidxPair(
            videoData: vData,
            audioData: aData
        ) else {
            return nil
        }
        logSidxParsed(
            parsed.video,
            parsed.audio,
            since: startTime
        )
        return buildPlayerItem(
            input: input,
            videoSegments: parsed.video,
            audioSegments: parsed.audio,
            startTime: startTime
        )
    }

    static func parseSidxPair(
        videoData: Data,
        audioData: Data
    ) -> (video: [SidxSegment], audio: [SidxSegment])? {
        guard let vSegs = HLSGenerator.parseSidx(
            data: videoData
        ) else {
            AppLog.hls("failed to parse video sidx")
            return nil
        }
        guard let aSegs = HLSGenerator.parseSidx(
            data: audioData
        ) else {
            AppLog.hls("failed to parse audio sidx")
            return nil
        }
        return (vSegs, aSegs)
    }

    static func logSidxParsed(
        _ videoSegs: [SidxSegment],
        _ audioSegs: [SidxSegment],
        since startTime: CFTimeInterval
    ) {
        let elapsed = CACurrentMediaTime() - startTime
        let msg = String(
            format: "sidx parsed in %.1fs — v:%d a:%d",
            elapsed,
            videoSegs.count,
            audioSegs.count
        )
        AppLog.hls(msg)
    }

    static func buildPlayerItem(
        input: BuildInput,
        videoSegments: [SidxSegment],
        audioSegments: [SidxSegment],
        startTime: CFTimeInterval
    ) -> Result? {
        let loader = createPlaylistLoader(
            input: input,
            videoSegments: videoSegments,
            audioSegments: audioSegments
        )
        let elapsed = CACurrentMediaTime() - startTime
        let msg = String(
            format: "playlists ready in %.1fs",
            elapsed
        )
        AppLog.hls(msg)
        let urlStr = "\(HLSGenerator.scheme)://master.m3u8"
        guard let plURL = URL(string: urlStr) else {
            return nil
        }
        let opts: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": input.headers
        ]
        let asset = AVURLAsset(url: plURL, options: opts)
        asset.resourceLoader.setDelegate(
            loader,
            queue: loader.loaderQueue
        )
        let item = AVPlayerItem(asset: asset)
        PlaybackBufferPolicy.configure(item: item)
        return Result(playerItem: item, loader: loader)
    }

    static func createPlaylistLoader(
        input: BuildInput,
        videoSegments: [SidxSegment],
        audioSegments: [SidxSegment]
    ) -> HLSPlaylistLoader {
        let loader = HLSPlaylistLoader()
        registerMediaPlaylists(
            on: loader,
            input: input,
            videoSegments: videoSegments,
            audioSegments: audioSegments
        )
        registerMainPlaylists(on: loader, input: input)
        return loader
    }

    static func registerMediaPlaylists(
        on loader: HLSPlaylistLoader,
        input: BuildInput,
        videoSegments: [SidxSegment],
        audioSegments: [SidxSegment]
    ) {
        let vidFmt = input.videoFormat
        let audFmt = input.audioFormat
        let videoPl = HLSGenerator.mediaPlaylist(
            url: input.videoURL,
            initBytes: vidFmt.initRangeEnd + 1,
            dataStartOffset: Int64(vidFmt.indexRangeEnd + 1),
            segments: videoSegments
        )
        let audioPl = HLSGenerator.mediaPlaylist(
            url: input.audioURL,
            initBytes: audFmt.initRangeEnd + 1,
            dataStartOffset: Int64(audFmt.indexRangeEnd + 1),
            segments: audioSegments
        )
        loader.register(path: "video.m3u8", content: videoPl)
        loader.register(path: "audio.m3u8", content: audioPl)
    }

    static func registerMainPlaylists(
        on loader: HLSPlaylistLoader,
        input: BuildInput
    ) {
        let vidFmt = input.videoFormat
        let audFmt = input.audioFormat
        let scheme = HLSGenerator.scheme
        let uris = HLSGenerator.PlaylistURIs(
            video: "\(scheme)://video.m3u8",
            audio: "\(scheme)://audio.m3u8"
        )
        let codecs = "\(vidFmt.codecs),\(audFmt.codecs)"
        let width = vidFmt.width ?? 1_280
        let height = vidFmt.height ?? 720
        let mainPl = HLSGenerator.mainPlaylist(
            bandwidth: vidFmt.bitrate,
            codecs: codecs,
            resolution: "\(width)x\(height)",
            uris: uris
        )
        loader.register(path: "master.m3u8", content: mainPl)
        let audioOnlyPl = HLSGenerator.audioOnlyMainPlaylist(
            audioCodecs: audFmt.codecs,
            audioBandwidth: audFmt.bitrate,
            audioPlaylistURI: uris.audio
        )
        loader.register(
            path: "audio-master.m3u8",
            content: audioOnlyPl
        )
    }
}
