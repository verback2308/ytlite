import Foundation

extension InnertubeClient {

    // MARK: - JSON parsing

    static func parseWatchPage(_ json: [String: Any], fallbackVideo: Video) -> WatchPage? {
        let metadata = parseWatchMetadata(json)
        let channelInfo = parseWatchChannelInfo(json, fallbackVideo: fallbackVideo)
        let subscribeState = parseSubscribeState(json)
        let description = parseWatchDescription(json)

        let resolvedVideo = Video(
            id: fallbackVideo.id,
            title: metadata.title ?? fallbackVideo.title,
            channelId: channelInfo?.id ?? fallbackVideo.channelId,
            channelName: channelInfo?.title.isEmpty == false ? channelInfo!.title : fallbackVideo.channelName,
            channelAvatarURL: channelInfo?.avatarURL ?? fallbackVideo.channelAvatarURL,
            thumbnailURL: fallbackVideo.thumbnailURL,
            viewCount: metadata.viewCountText ?? fallbackVideo.viewCount,
            publishedAt: metadata.publishedText ?? fallbackVideo.publishedAt,
            duration: fallbackVideo.duration,
            isLive: fallbackVideo.isLive
        )

        let relatedVideos = collectTileRenderers(in: json)
            .compactMap(parseTileRenderer)
            .filter { $0.id != fallbackVideo.id }
            .reduce(into: [Video]()) { partialResult, video in
                if partialResult.contains(where: { $0.id == video.id }) { return }
                partialResult.append(video)
            }

        let likeInfo = InnertubeClient.parseWatchLikeInfo(json)

        // Parse autoplay next video from playerOverlays
        let nextVideo: Video? = {
            guard let ar = (json["playerOverlays"] as? [String: Any])
                .flatMap({ $0["playerOverlayRenderer"] as? [String: Any] })
                .flatMap({ $0["autoplay"] as? [String: Any] })
                .flatMap({ $0["playerOverlayAutoplayRenderer"] as? [String: Any] })
            else { return nil }
            guard let videoId = ar["videoId"] as? String else { return nil }
            let title = (ar["videoTitle"] as? [String: Any])?["simpleText"] as? String ?? ""
            let channel = (ar["byline"] as? [String: Any])?["simpleText"] as? String ?? ""
            let thumbs = (ar["background"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let thumbURL = thumbs?.last?["url"] as? String ?? thumbs?.first?["url"] as? String
                ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
            return Video(id: videoId, title: title, channelId: nil, channelName: channel,
                         channelAvatarURL: nil, thumbnailURL: thumbURL,
                         viewCount: nil, publishedAt: nil, duration: nil)
        }()

        return WatchPage(video: resolvedVideo,
                         description: description,
                         channelInfo: channelInfo,
                         subscribeButtonText: subscribeState.text,
                         isSubscribed: subscribeState.isSubscribed,
                         relatedVideos: relatedVideos,
                         likeCount: likeInfo.likeCount,
                         likeStatus: likeInfo.likeStatus,
                         nextVideo: nextVideo)
    }

    static func parseWatchLikeInfo(_ json: [String: Any]) -> (likeCount: String?, likeStatus: LikeStatus?) {
        if let actionsRenderer = firstRenderer(in: json, named: "slimVideoActionsRenderer"),
           let buttons = actionsRenderer["buttons"] as? [[String: Any]] {
            for btn in buttons {
                if let likeBtn = (btn["slimMetadataToggleButtonRenderer"] as? [String: Any])
                    ?? (btn["likeButtonRenderer"] as? [String: Any]) {
                    let statusStr = likeBtn["likeStatus"] as? String
                    let status = statusStr.flatMap(LikeStatus.init(rawValue:))
                    let count = simpleText(from: likeBtn["defaultText"])
                        ?? simpleText(from: likeBtn["likeCountNotliked"])
                    return (count, status)
                }
                if let toggle = btn["toggleButtonRenderer"] as? [String: Any] {
                    let statusStr = toggle["likeStatus"] as? String
                    let status = statusStr.flatMap(LikeStatus.init(rawValue:))
                    let count = simpleText(from: toggle["defaultText"])
                    return (count, status)
                }
            }
        }
        if let renderer = firstRenderer(in: json, named: "likeButtonRenderer") {
            let statusStr = renderer["likeStatus"] as? String
            let status = statusStr.flatMap(LikeStatus.init(rawValue:))
            let count = simpleText(from: renderer["likeCount"])
                ?? (renderer["likeCountNotliked"] as? String)
            return (count, status)
        }
        return (nil, nil)
    }

    static func parseCommentsPage(_ json: [String: Any]) -> CommentsPage? {
        let mutations = ((((json["frameworkUpdates"] as? [String: Any])?["entityBatchUpdate"] as? [String: Any])?["mutations"]) as? [[String: Any]]) ?? []
        let threads = collectCommentThreads(in: json)
        let comments = threads.compactMap { parseComment(from: $0, mutations: mutations) }
        let continuation = findCommentsContinuation(in: json)
        let title = findCommentsTitle(in: json)

        guard !comments.isEmpty || continuation != nil else { return nil }
        return CommentsPage(title: title, comments: comments, continuation: continuation)
    }

    static func parsePlayerJSON(_ json: [String: Any]) -> DirectPlaybackInfo? {
        let topKeys = json.keys.sorted().joined(separator: ", ")
        print("[InnertubeClient] parsePlayerJSON topKeys: \(topKeys)")
        if let sd = json["streamingData"] as? [String: Any] {
            let formats = (sd["formats"] as? [[String: Any]])?.count ?? 0
            let adaptive = (sd["adaptiveFormats"] as? [[String: Any]])?.count ?? 0
            print("[InnertubeClient] streamingData found: formats=\(formats) adaptive=\(adaptive)")
        } else {
            print("[InnertubeClient] streamingData MISSING — playabilityStatus: \((json["playabilityStatus"] as? [String: Any])?["status"] ?? "nil")")
        }
        return parseDirectPlaybackInfo(json)
    }

    static func parseDirectPlaybackInfo(_ json: [String: Any]) -> DirectPlaybackInfo? {
        guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

        let formats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []

        func directURL(_ format: [String: Any]) -> URL? {
            guard let value = format["url"] as? String, !value.isEmpty else { return nil }
            return URL(string: value)
        }

        func mimeType(_ format: [String: Any]) -> String {
            format["mimeType"] as? String ?? ""
        }

        func height(_ format: [String: Any]) -> Int {
            format["height"] as? Int ?? 0
        }

        func bitrate(_ format: [String: Any]) -> Int {
            format["bitrate"] as? Int ?? 0
        }

        func itag(_ format: [String: Any]) -> Int? {
            format["itag"] as? Int
        }

        func sabrFormatInfo(_ format: [String: Any]) -> SabrFormatInfo? {
            guard let formatItag = itag(format) else { return nil }
            let audioTrack = format["audioTrack"] as? [String: Any]
            return SabrFormatInfo(
                itag: formatItag,
                lastModified: (format["lastModified"] as? String) ?? (format["lmt"] as? String),
                xtags: format["xtags"] as? String,
                audioTrackId: audioTrack?["id"] as? String,
                isDrc: (format["isDrc"] as? Bool) ?? ((format["xtags"] as? String)?.contains("drc=1") == true),
                mimeType: format["mimeType"] as? String,
                bitrate: format["bitrate"] as? Int,
                width: format["width"] as? Int,
                height: format["height"] as? Int
            )
        }

        let progressive = formats
            .filter { directURL($0) != nil && mimeType($0).contains("video/mp4") }
            .sorted { bitrate($0) > bitrate($1) }
            .first

        let preferredMaxHeight = VideoQualityStore.maxHeight   // nil = Auto

        let video = adaptiveFormats
            .filter {
                directURL($0) != nil &&
                mimeType($0).contains("video/mp4") &&
                mimeType($0).contains("avc1") &&
                height($0) > 0 &&
                (preferredMaxHeight == nil || height($0) <= preferredMaxHeight!)
            }
            .sorted { lhs, rhs in
                let lhsHeight = height(lhs)
                let rhsHeight = height(rhs)
                if lhsHeight == rhsHeight {
                    return bitrate(lhs) > bitrate(rhs)
                }
                return lhsHeight > rhsHeight
            }
            .first

        let audio = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("audio/mp4") }
            .sorted { bitrate($0) > bitrate($1) }
            .first

        // Extract DASH format info (initRange/indexRange) for MPD generation
        func dashFormatInfo(_ format: [String: Any]) -> DashFormatInfo? {
            guard let url = directURL(format),
                  let formatItag = itag(format),
                  let initRange = format["initRange"] as? [String: Any],
                  let initEnd = (initRange["end"] as? String).flatMap(Int.init) ?? (initRange["end"] as? Int),
                  let indexRange = format["indexRange"] as? [String: Any],
                  let indexStart = (indexRange["start"] as? String).flatMap(Int.init) ?? (indexRange["start"] as? Int),
                  let indexEnd = (indexRange["end"] as? String).flatMap(Int.init) ?? (indexRange["end"] as? Int),
                  let clen = (format["contentLength"] as? String).flatMap(Int64.init) else {
                return nil
            }
            let mime = mimeType(format)
            // Extract codecs from mimeType like "video/mp4; codecs=\"avc1.4d401f\""
            let codecs: String
            if let range = mime.range(of: "codecs=\""), let endRange = mime[range.upperBound...].range(of: "\"") {
                codecs = String(mime[range.upperBound..<endRange.lowerBound])
            } else {
                codecs = ""
            }
            return DashFormatInfo(
                url: url, itag: formatItag, mimeType: mime, codecs: codecs,
                bitrate: bitrate(format), contentLength: clen,
                initRangeEnd: initEnd, indexRangeStart: indexStart, indexRangeEnd: indexEnd,
                width: format["width"] as? Int, height: format["height"] as? Int,
                fps: format["fps"] as? Int
            )
        }

        let dashVideoFormat = video.flatMap(dashFormatInfo)
        let dashAudioFormat = audio.flatMap(dashFormatInfo)

        // All video qualities with DASH support (initRange/indexRange present), sorted best→worst
        let allDashVideoFormats: [DashFormatInfo] = adaptiveFormats
            .filter {
                directURL($0) != nil &&
                mimeType($0).contains("video/mp4") &&
                mimeType($0).contains("avc1") &&
                height($0) > 0
            }
            .compactMap(dashFormatInfo)
            .sorted { lhs, rhs in
                let lh = lhs.height ?? 0, rh = rhs.height ?? 0
                if lh == rh { return lhs.bitrate > rhs.bitrate }
                return lh > rh
            }
        if let dv = dashVideoFormat {
            print("[Innertube] DASH video: itag=\(dv.itag) init=0-\(dv.initRangeEnd) index=\(dv.indexRangeStart)-\(dv.indexRangeEnd) clen=\(dv.contentLength) codecs=\(dv.codecs)")
        }
        if let da = dashAudioFormat {
            print("[Innertube] DASH audio: itag=\(da.itag) init=0-\(da.initRangeEnd) index=\(da.indexRangeStart)-\(da.indexRangeEnd) clen=\(da.contentLength) codecs=\(da.codecs)")
        }

        // Extract duration from format
        let videoDuration = (video?["approxDurationMs"] as? String).flatMap(Double.init).map { $0 / 1000.0 }
            ?? (audio?["approxDurationMs"] as? String).flatMap(Double.init).map { $0 / 1000.0 }

        let hlsManifestURL = (streamingData["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
        let dashManifestURL = (streamingData["dashManifestUrl"] as? String).flatMap(URL.init(string:))
        let progressiveURL = progressive.flatMap(directURL)
        let videoURL = video.flatMap(directURL)
        let audioURL = audio.flatMap(directURL)
        let serverAbrStreamingURL = (streamingData["serverAbrStreamingUrl"] as? String).flatMap(URL.init(string:))
        let mediaCommonConfig = (json["playerConfig"] as? [String: Any])?["mediaCommonConfig"] as? [String: Any]
        let mediaUstreamerRequestConfig = mediaCommonConfig?["mediaUstreamerRequestConfig"] as? [String: Any]
        let videoPlaybackUstreamerConfig = mediaUstreamerRequestConfig?["videoPlaybackUstreamerConfig"] as? String
        let onesieUstreamerConfig = mediaUstreamerRequestConfig?["onesieUstreamerConfig"] as? String
        let hasVideoPlaybackUstreamerConfig = videoPlaybackUstreamerConfig?.isEmpty == false

        guard hlsManifestURL != nil || dashManifestURL != nil || progressiveURL != nil || (videoURL != nil && audioURL != nil) || serverAbrStreamingURL != nil else {
            return nil
        }

        return DirectPlaybackInfo(
            hlsManifestURL: hlsManifestURL,
            dashManifestURL: dashManifestURL,
            progressiveURL: progressiveURL,
            videoURL: videoURL,
            audioURL: audioURL,
            serverAbrStreamingURL: serverAbrStreamingURL,
            videoPlaybackUstreamerConfig: videoPlaybackUstreamerConfig,
            onesieUstreamerConfig: onesieUstreamerConfig,
            sabrVideoFormat: video.flatMap(sabrFormatInfo),
            sabrAudioFormat: audio.flatMap(sabrFormatInfo),
            videoItag: video.flatMap(itag) ?? progressive.flatMap(itag),
            audioItag: audio.flatMap(itag),
            qualityLabel: (video?["qualityLabel"] as? String) ?? (progressive?["qualityLabel"] as? String),
            visitorData: ((json["responseContext"] as? [String: Any])?["visitorData"] as? String),
            hasVideoPlaybackUstreamerConfig: hasVideoPlaybackUstreamerConfig,
            dashVideoFormat: dashVideoFormat,
            dashAudioFormat: dashAudioFormat,
            allDashVideoFormats: allDashVideoFormats,
            duration: videoDuration
        )
    }

    static func logPlayerDebug(videoId: String, contextName: String, json: [String: Any]) {
        let playability = json["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String ?? "nil"
        let reason = playability?["reason"] as? String ?? "nil"
        let streamingData = json["streamingData"] as? [String: Any]
        let formats = streamingData?["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData?["adaptiveFormats"] as? [[String: Any]] ?? []
        let hlsManifestURL = streamingData?["hlsManifestUrl"] as? String ?? "nil"
        let dashManifestURL = streamingData?["dashManifestUrl"] as? String ?? "nil"
        let sabrURL = streamingData?["serverAbrStreamingUrl"] as? String ?? "nil"

        func summarize(_ format: [String: Any]) -> String {
            let itag = format["itag"] as? Int ?? -1
            let mimeType = format["mimeType"] as? String ?? "nil"
            let hasURL = (format["url"] as? String)?.isEmpty == false
            let hasCipher = (format["signatureCipher"] as? String)?.isEmpty == false || (format["cipher"] as? String)?.isEmpty == false
            let quality = (format["qualityLabel"] as? String) ?? (format["audioQuality"] as? String) ?? "nil"
            return "itag=\(itag), quality=\(quality), mime=\(mimeType), url=\(hasURL), cipher=\(hasCipher)"
        }

        let formatSummary = formats.prefix(3).map(summarize).joined(separator: " | ")
        let adaptiveSummary = adaptiveFormats.prefix(5).map(summarize).joined(separator: " | ")

        print("[Innertube] player debug (\(contextName)) \(videoId): status=\(status), reason=\(reason)")
        print("[Innertube] player debug (\(contextName)) manifests: hls=\(hlsManifestURL), dash=\(dashManifestURL), sabr=\(sabrURL)")
        print("[Innertube] player debug (\(contextName)) formats=\(formats.count) [\(formatSummary)]")
        print("[Innertube] player debug (\(contextName)) adaptive=\(adaptiveFormats.count) [\(adaptiveSummary)]")

        if contextName == "TVHTML5" {
            logDirectPlaybackCandidates(videoId: videoId, formats: formats, adaptiveFormats: adaptiveFormats)
        }
    }

    static func logDirectPlaybackCandidates(videoId: String, formats: [[String: Any]], adaptiveFormats: [[String: Any]]) {
        func stringValue(_ format: [String: Any], key: String) -> String {
            format[key] as? String ?? "nil"
        }

        func directURL(_ format: [String: Any]) -> String? {
            let url = format["url"] as? String
            return url?.isEmpty == false ? url : nil
        }

        func mimeType(_ format: [String: Any]) -> String {
            format["mimeType"] as? String ?? ""
        }

        func height(_ format: [String: Any]) -> Int {
            format["height"] as? Int ?? 0
        }

        func bitrate(_ format: [String: Any]) -> Int {
            format["bitrate"] as? Int ?? 0
        }

        func itag(_ format: [String: Any]) -> Int {
            format["itag"] as? Int ?? -1
        }

        let progressive = formats
            .filter { directURL($0) != nil }
            .sorted { bitrate($0) > bitrate($1) }

        let videoCandidates = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("video/mp4") && mimeType($0).contains("avc1") }
            .sorted { lhs, rhs in
                let lhsHeight = height(lhs)
                let rhsHeight = height(rhs)
                if lhsHeight == rhsHeight {
                    return bitrate(lhs) > bitrate(rhs)
                }
                return lhsHeight > rhsHeight
            }

        let audioCandidates = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("audio/mp4") }
            .sorted { bitrate($0) > bitrate($1) }

        if let bestProgressive = progressive.first, let url = directURL(bestProgressive) {
            let quality = stringValue(bestProgressive, key: "qualityLabel")
            print("[Innertube] player direct (\(videoId)) progressive: itag=\(itag(bestProgressive)), quality=\(quality), mime=\(mimeType(bestProgressive)), bitrate=\(bitrate(bestProgressive)), url=\(url)")
        } else {
            print("[Innertube] player direct (\(videoId)) progressive: none")
        }

        let topVideoSummary = videoCandidates.prefix(3).map {
            let quality = stringValue($0, key: "qualityLabel")
            return "itag=\(itag($0)), quality=\(quality), bitrate=\(bitrate($0)), mime=\(mimeType($0))"
        }.joined(separator: " | ")
        let topAudioSummary = audioCandidates.prefix(3).map {
            let audioQuality = stringValue($0, key: "audioQuality")
            return "itag=\(itag($0)), audio=\(audioQuality), bitrate=\(bitrate($0)), mime=\(mimeType($0))"
        }.joined(separator: " | ")

        print("[Innertube] player direct (\(videoId)) mp4 video candidates: \(videoCandidates.count) [\(topVideoSummary)]")
        print("[Innertube] player direct (\(videoId)) mp4 audio candidates: \(audioCandidates.count) [\(topAudioSummary)]")

        if let bestVideo = videoCandidates.first, let bestAudio = audioCandidates.first,
           let videoURL = directURL(bestVideo), let audioURL = directURL(bestAudio) {
            let videoQuality = stringValue(bestVideo, key: "qualityLabel")
            let audioQuality = stringValue(bestAudio, key: "audioQuality")
            print("[Innertube] player direct (\(videoId)) selected video: itag=\(itag(bestVideo)), quality=\(videoQuality), url=\(videoURL)")
            print("[Innertube] player direct (\(videoId)) selected audio: itag=\(itag(bestAudio)), quality=\(audioQuality), url=\(audioURL)")
        }
    }

    static func parsePageJSON(_ json: [String: Any]) -> FeedPage {
        // Continuation response
        if let cc = json["continuationContents"] as? [String: Any],
           let slr = cc["sectionListContinuation"] as? [String: Any] {
            return parseSectionList(slr)
        }
        // Initial browse response
        if let slr = extractSectionList(from: json) {
            return parseSectionList(slr)
        }
        let contentsKeys = (json["contents"] as? [String: Any])?.keys.joined(separator: ", ") ?? "nil"
        print("[Innertube] parsePageJSON: unrecognized structure. contents keys: \(contentsKeys)")
        return FeedPage(videos: [], continuation: nil)
    }

    static func extractSectionList(from json: [String: Any]) -> [String: Any]? {
        let tvBrowse = (json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any]
        let content = tvBrowse?["content"] as? [String: Any]

        // Home feed path
        if let tvSurface = content?["tvSurfaceContentRenderer"] as? [String: Any],
           let slr = (tvSurface["content"] as? [String: Any])?["sectionListRenderer"] as? [String: Any] {
            return slr
        }

        // Subscriptions path
        if let nav = content?["tvSecondaryNavRenderer"] as? [String: Any],
           let sections = nav["sections"] as? [[String: Any]],
           let tabs = (sections.first?["tvSecondaryNavSectionRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]],
           let tabContent = (tabs.first?["tabRenderer"] as? [String: Any])?["content"] as? [String: Any],
           let tvSurface = tabContent["tvSurfaceContentRenderer"] as? [String: Any],
           let slr = (tvSurface["content"] as? [String: Any])?["sectionListRenderer"] as? [String: Any] {
            return slr
        }
        return nil
    }

    static func parseSectionList(_ slr: [String: Any]) -> FeedPage {
        let sections = slr["contents"] as? [[String: Any]] ?? []
        var videos: [Video] = []

        for section in sections {
            guard let shelf = section["shelfRenderer"] as? [String: Any],
                  let shelfContent = shelf["content"] as? [String: Any]
            else { continue }

            // Horizontal shelf (main format for home/subscriptions)
            if let items = (shelfContent["horizontalListRenderer"] as? [String: Any])?["items"] as? [[String: Any]] {
                for item in items {
                    if let tile = item["tileRenderer"] as? [String: Any],
                       let video = parseTileRenderer(tile) { videos.append(video) }
                }
            }

            // Vertical list shelf (used for some content types)
            if let items = (shelfContent["verticalListRenderer"] as? [String: Any])?["items"] as? [[String: Any]] {
                for item in items {
                    if let tile = item["tileRenderer"] as? [String: Any],
                       let video = parseTileRenderer(tile) { videos.append(video) }
                    if let vr = item["videoRenderer"] as? [String: Any],
                       let video = parseWebVideoRenderer(vr) { videos.append(video) }
                }
            }

            // Grid inside shelf
            if let items = (shelfContent["gridRenderer"] as? [String: Any])?["items"] as? [[String: Any]] {
                for item in items {
                    if let tile = item["tileRenderer"] as? [String: Any],
                       let video = parseTileRenderer(tile) { videos.append(video) }
                }
            }
        }

        let continuation = (slr["continuations"] as? [[String: Any]])?
            .first.flatMap { ($0["nextContinuationData"] as? [String: Any])?["continuation"] as? String }

        return FeedPage(videos: videos, continuation: continuation)
    }

}
