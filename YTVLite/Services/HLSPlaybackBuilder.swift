import AVFoundation

/// Builds HLS playlists from DASH adaptive format info by fetching SIDX indexes
/// and generating byte-range HLS playlists served via a custom URL scheme.
enum HLSPlaybackBuilder {

    struct Result {
        let playerItem: AVPlayerItem
        let loader: HLSPlaylistLoader
    }

    /// Fetches SIDX data for both streams, generates HLS playlists, and returns a ready-to-play AVPlayerItem.
    static func build(videoURL: URL, audioURL: URL,
                      videoFormat: DashFormatInfo, audioFormat: DashFormatInfo,
                      headers: [String: String],
                      completion: @escaping (Result?) -> Void) {
        let startTime = CACurrentMediaTime()

        let group = DispatchGroup()
        var videoSidxData: Data?
        var audioSidxData: Data?

        group.enter()
        fetchRangeData(url: videoURL,
                       start: Int64(videoFormat.indexRangeStart),
                       end: Int64(videoFormat.indexRangeEnd),
                       headers: headers) { data in
            videoSidxData = data
            group.leave()
        }

        group.enter()
        fetchRangeData(url: audioURL,
                       start: Int64(audioFormat.indexRangeStart),
                       end: Int64(audioFormat.indexRangeEnd),
                       headers: headers) { data in
            audioSidxData = data
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            guard let vData = videoSidxData, let aData = audioSidxData else {
                AppLog.hls("failed to fetch sidx data")
                completion(nil)
                return
            }

            guard let videoSegments = HLSGenerator.parseSidx(data: vData),
                  let audioSegments = HLSGenerator.parseSidx(data: aData) else {
                AppLog.hls("failed to parse sidx (video=\(vData.count)B audio=\(aData.count)B)")
                completion(nil)
                return
            }

            let fetchElapsed = CACurrentMediaTime() - startTime
            AppLog.hls(String(format: "sidx parsed in %.1fs — video: %d segments, audio: %d segments",
                         fetchElapsed, videoSegments.count, audioSegments.count))

            let videoInitBytes = videoFormat.initRangeEnd + 1
            let audioInitBytes = audioFormat.initRangeEnd + 1
            let videoDataStart = Int64(videoFormat.indexRangeEnd + 1)
            let audioDataStart = Int64(audioFormat.indexRangeEnd + 1)

            let videoPlaylist = HLSGenerator.mediaPlaylist(url: videoURL, initBytes: videoInitBytes,
                                                           dataStartOffset: videoDataStart, segments: videoSegments)
            let audioPlaylist = HLSGenerator.mediaPlaylist(url: audioURL, initBytes: audioInitBytes,
                                                           dataStartOffset: audioDataStart, segments: audioSegments)

            let videoWidth = videoFormat.width ?? 1280
            let videoHeight = videoFormat.height ?? 720
            let masterPlaylist = HLSGenerator.masterPlaylist(
                videoBandwidth: videoFormat.bitrate,
                videoCodecs: videoFormat.codecs,
                audioCodecs: audioFormat.codecs,
                width: videoWidth, height: videoHeight,
                videoPlaylistURI: "\(HLSGenerator.scheme)://video.m3u8",
                audioPlaylistURI: "\(HLSGenerator.scheme)://audio.m3u8"
            )

            let loader = HLSPlaylistLoader()
            loader.register(path: "master.m3u8", content: masterPlaylist)
            loader.register(path: "video.m3u8", content: videoPlaylist)
            loader.register(path: "audio.m3u8", content: audioPlaylist)

            let audioOnlyMaster = HLSGenerator.audioOnlyMasterPlaylist(
                audioCodecs: audioFormat.codecs,
                audioBandwidth: audioFormat.bitrate,
                audioPlaylistURI: "\(HLSGenerator.scheme)://audio.m3u8"
            )
            loader.register(path: "audio-master.m3u8", content: audioOnlyMaster)

            let totalElapsed = CACurrentMediaTime() - startTime
            AppLog.hls(String(format: "playlists ready in %.1fs", totalElapsed))

            let masterURL = URL(string: "\(HLSGenerator.scheme)://master.m3u8")!
            let assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let asset = AVURLAsset(url: masterURL, options: assetOptions)
            asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 5.0

            completion(Result(playerItem: item, loader: loader))
        }
    }

    /// Fetch a byte range from a URL with custom headers.
    static func fetchRangeData(url: URL, start: Int64, end: Int64,
                               headers: [String: String],
                               completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: HTTPHeader.range)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                AppLog.hls("range fetch failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 206 && status != 200 {
                AppLog.hls("range fetch status \(status)")
            }
            completion(data)
        }.resume()
    }
}
