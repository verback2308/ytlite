// swiftlint:disable file_length
import Foundation

extension InnertubeClient {
    static func parsePlayerJSON(
        _ json: [String: Any]
    ) -> DirectPlaybackInfo? {
        logStreamingDataSummary(json)
        return parseDirectPlaybackInfo(json)
    }

    static func parseDirectPlaybackInfo(
        _ json: [String: Any]
    ) -> DirectPlaybackInfo? {
        guard let sd = json["streamingData"]
            as? [String: Any]
        else {
            return nil
        }
        let formats = sd["formats"]
            as? [[String: Any]] ?? []
        let adaptive = sd["adaptiveFormats"]
            as? [[String: Any]] ?? []
        let selected = selectFormats(
            formats: formats,
            adaptive: adaptive
        )
        return assemblePlayback(
            json: json,
            streamingData: sd,
            selected: selected,
            adaptive: adaptive
        )
    }

    static func fmtDirectURL(
        _ format: [String: Any]
    ) -> URL? {
        guard let val = format["url"] as? String,
              !val.isEmpty
        else {
            return nil
        }
        return URL(string: val)
    }

    static func fmtURLString(
        _ format: [String: Any]
    ) -> String? {
        let url = format["url"] as? String
        return url?.isEmpty == false ? url : nil
    }

    static func fmtMimeType(
        _ format: [String: Any]
    ) -> String {
        format["mimeType"] as? String ?? ""
    }

    static func fmtHeight(
        _ format: [String: Any]
    ) -> Int { format["height"] as? Int ?? 0 }

    static func fmtBitrate(
        _ format: [String: Any]
    ) -> Int { format["bitrate"] as? Int ?? 0 }

    static func fmtItag(
        _ format: [String: Any]
    ) -> Int? { format["itag"] as? Int }

    static func heightBitrateLess(
        _ lhs: [String: Any],
        _ rhs: [String: Any]
    ) -> Bool {
        let leftHeight = fmtHeight(lhs)
        let rightHeight = fmtHeight(rhs)
        if leftHeight == rightHeight {
            return fmtBitrate(lhs)
                < fmtBitrate(rhs)
        }
        return leftHeight < rightHeight
    }
}

// MARK: - Format Selection & DASH Builders

private extension InnertubeClient {
    static func selectFormats(
        formats: [[String: Any]],
        adaptive: [[String: Any]]
    ) -> SelectedFmts {
        let progressive = formats
            .filter {
                fmtDirectURL($0) != nil
                    && fmtMimeType($0)
                        .contains("video/mp4")
            }
            .max {
                fmtBitrate($0) < fmtBitrate($1)
            }
        let video = selectBestVideo(
            from: adaptive,
            maxHeight: VideoQualityStore.maxHeight
        )
        let audio = adaptive
            .filter {
                fmtDirectURL($0) != nil
                    && fmtMimeType($0)
                        .contains("audio/mp4")
            }
            .max {
                fmtBitrate($0) < fmtBitrate($1)
            }
        return SelectedFmts(
            progressive: progressive,
            video: video,
            audio: audio
        )
    }

    static func selectBestVideo(
        from adaptive: [[String: Any]],
        maxHeight: Int?
    ) -> [String: Any]? {
        adaptive
            .filter { fmt in
                fmtDirectURL(fmt) != nil
                    && fmtMimeType(fmt)
                        .contains("video/mp4")
                    && fmtMimeType(fmt)
                        .contains("avc1")
                    && fmtHeight(fmt) > 0
                    && maxHeight.map {
                        fmtHeight(fmt) <= $0
                    } ?? true
            }
            .max { heightBitrateLess($0, $1) }
    }

    static func buildSabrInfo(
        _ fmt: [String: Any]
    ) -> SabrFormatInfo? {
        guard let tag = fmtItag(fmt)
        else {
            return nil
        }
        let audioTrack = fmt["audioTrack"]
            as? [String: Any]
        let xtags = fmt["xtags"] as? String
        let isDrc = (fmt["isDrc"] as? Bool)
            ?? (xtags?.contains("drc=1") == true)
        return SabrFormatInfo(
            itag: tag,
            lastModified:
                (fmt["lastModified"] as? String)
                ?? (fmt["lmt"] as? String),
            xtags: xtags,
            audioTrackId: audioTrack?["id"] as? String,
            isDrc: isDrc,
            mimeType: fmt["mimeType"] as? String,
            bitrate: fmt["bitrate"] as? Int,
            width: fmt["width"] as? Int,
            height: fmt["height"] as? Int
        )
    }

    static func buildDashInfo(
        _ fmt: [String: Any]
    ) -> DashFormatInfo? {
        let initRange = fmt["initRange"]
            as? [String: Any]
        let indexRange = fmt["indexRange"]
            as? [String: Any]
        guard let url = fmtDirectURL(fmt),
              let tag = fmtItag(fmt),
              let initEnd = intVal(initRange?["end"]),
              let indexStart = intVal(indexRange?["start"]),
              let indexEnd = intVal(indexRange?["end"]),
              let contentLength = (fmt["contentLength"]
                  as? String).flatMap(Int64.init)
        else {
            return nil
        }
        return makeDashInfo(
            url: url,
            itag: tag,
            fmt: fmt,
            clen: contentLength,
            iEnd: initEnd,
            xSt: indexStart,
            xEnd: indexEnd
        )
    }

    // swiftlint:disable function_parameter_count
    static func makeDashInfo(
        url: URL,
        itag: Int,
        fmt: [String: Any],
        clen: Int64,
        iEnd: Int,
        xSt: Int,
        xEnd: Int
    ) -> DashFormatInfo {
        DashFormatInfo(
            url: url,
            itag: itag,
            mimeType: fmtMimeType(fmt),
            codecs: extractCodecs(
                from: fmtMimeType(fmt)
            ),
            bitrate: fmtBitrate(fmt),
            contentLength: clen,
            initRangeEnd: iEnd,
            indexRangeStart: xSt,
            indexRangeEnd: xEnd,
            width: fmt["width"] as? Int,
            height: fmt["height"] as? Int,
            fps: fmt["fps"] as? Int
        )
    }
    // swiftlint:enable function_parameter_count

    static func intVal(_ value: Any?) -> Int? {
        if let str = value as? String {
            return Int(str)
        }
        return value as? Int
    }

    static func extractCodecs(
        from mime: String
    ) -> String {
        guard let start = mime.range(
            of: "codecs=\""
        ),
              let end = mime[start.upperBound...]
                  .range(of: "\"")
        else {
            return ""
        }
        return String(
            mime[
                start.upperBound..<end.lowerBound
            ]
        )
    }

    static func buildAllDashVideo(
        from adaptive: [[String: Any]]
    ) -> [DashFormatInfo] {
        adaptive
            .filter {
                fmtDirectURL($0) != nil
                    && fmtMimeType($0)
                        .contains("video/mp4")
                    && fmtMimeType($0)
                        .contains("avc1")
                    && fmtHeight($0) > 0
            }
            .compactMap(buildDashInfo)
            .sorted { lhs, rhs in
                let lh = lhs.height ?? 0
                let rh = rhs.height ?? 0
                if lh == rh {
                    return lhs.bitrate > rhs.bitrate
                }
                return lh > rh
            }
    }
}

// MARK: - Playback Assembly

private extension InnertubeClient {
    static func assemblePlayback(
        json: [String: Any],
        streamingData sd: [String: Any],
        selected: SelectedFmts,
        adaptive: [[String: Any]]
    ) -> DirectPlaybackInfo? {
        let dashVideo = selected.video.flatMap(buildDashInfo)
        let dashAudio = selected.audio.flatMap(buildDashInfo)
        logDashSelection(video: dashVideo, audio: dashAudio)
        let urls = extractURLs(
            sd: sd, selected: selected
        )
        guard urls.hasAny
        else {
            return nil
        }
        let config = extractPlayerConfig(json: json)
        let allDash = buildAllDashVideo(
            from: adaptive
        )
        let duration = extractDuration(selected: selected)
        return buildPlaybackPart1(
            urls: urls,
            cfg: config,
            sel: selected,
            dV: dashVideo,
            dA: dashAudio,
            allDash: allDash,
            dur: duration,
            json: json
        )
    }

    // swiftlint:disable function_parameter_count
    // swiftlint:disable function_body_length
    static func buildPlaybackPart1(
        urls: PlaybackURLs,
        cfg: PlayerCfg,
        sel: SelectedFmts,
        dV: DashFormatInfo?,
        dA: DashFormatInfo?,
        allDash: [DashFormatInfo],
        dur: Double?,
        json: [String: Any]
    ) -> DirectPlaybackInfo {
        let vLabel = (sel.video?[
            "qualityLabel"
        ] as? String) ?? (sel.progressive?[
            "qualityLabel"
        ] as? String)
        let visitorData = (json["responseContext"]
            as? [String: Any])?["visitorData"]
            as? String
        let trackingURLs = extractWatchtimeURLs(json)
        let captions = extractCaptionTracks(json)
        return DirectPlaybackInfo(
            hlsManifestURL: urls.hls,
            dashManifestURL: urls.dash,
            progressiveURL: urls.progressive,
            videoURL: urls.video,
            audioURL: urls.audio,
            serverAbrStreamingURL: urls.sabr,
            videoPlaybackUstreamerConfig:
                cfg.playbackConfig,
            onesieUstreamerConfig:
                cfg.onesieConfig,
            sabrVideoFormat: sel.video
                .flatMap(buildSabrInfo),
            sabrAudioFormat: sel.audio
                .flatMap(buildSabrInfo),
            videoItag: sel.video
                .flatMap(fmtItag)
                ?? sel.progressive
                    .flatMap(fmtItag),
            audioItag: sel.audio
                .flatMap(fmtItag),
            qualityLabel: vLabel,
            visitorData: visitorData,
            hasPlaybackUstreamerConfig:
                cfg.hasPlaybackConfig,
            dashVideoFormat: dV,
            dashAudioFormat: dA,
            allDashVideoFormats: allDash,
            duration: dur,
            playbackTrackingURLs: trackingURLs,
            captionTracks: captions
        )
    }
    // swiftlint:enable function_body_length
    // swiftlint:enable function_parameter_count

    static func extractCaptionTracks(
        _ json: [String: Any]
    ) -> [SubtitleTrack] {
        guard let renderer = (json["captions"]
            as? [String: Any])?[
                "playerCaptionsTracklistRenderer"
            ] as? [String: Any],
              let tracks = renderer["captionTracks"]
                as? [[String: Any]]
        else {
            return []
        }
        return tracks.compactMap(buildSubtitleTrack)
    }

    private static func buildSubtitleTrack(
        _ track: [String: Any]
    ) -> SubtitleTrack? {
        guard let raw = track["baseUrl"] as? String,
              let url = URL(string: raw)
        else {
            return nil
        }
        let name = (track["name"]
            as? [String: Any])?["simpleText"]
            as? String
            ?? ((track["name"] as? [String: Any])?["runs"]
                as? [[String: Any]])?.first?["text"] as? String
            ?? (track["name"] as? String)
            ?? "Unknown"
        let lang = track["languageCode"] as? String ?? "und"
        let isAsr = (track["kind"] as? String) == "asr"
        return SubtitleTrack(
            name: name, languageCode: lang, url: url, isAsr: isAsr
        )
    }

    static func extractURLs(
        sd: [String: Any],
        selected sel: SelectedFmts
    ) -> PlaybackURLs {
        PlaybackURLs(
            hls: (sd["hlsManifestUrl"]
                as? String).flatMap(
                    URL.init(string:)
                ),
            dash: (sd["dashManifestUrl"]
                as? String).flatMap(
                    URL.init(string:)
                ),
            progressive: sel.progressive
                .flatMap(fmtDirectURL),
            video: sel.video
                .flatMap(fmtDirectURL),
            audio: sel.audio
                .flatMap(fmtDirectURL),
            sabr: (sd["serverAbrStreamingUrl"]
                as? String).flatMap(
                    URL.init(string:)
                )
        )
    }

    static func extractPlayerConfig(
        json: [String: Any]
    ) -> PlayerCfg {
        let pc = json["playerConfig"]
            as? [String: Any]
        let mc = pc?["mediaCommonConfig"]
            as? [String: Any]
        let rc = mc?[
            "mediaUstreamerRequestConfig"
        ] as? [String: Any]
        let vp = rc?[
            "videoPlaybackUstreamerConfig"
        ] as? String
        let oc = rc?[
            "onesieUstreamerConfig"
        ] as? String
        return PlayerCfg(
            playbackConfig: vp,
            onesieConfig: oc,
            hasPlaybackConfig:
                vp?.isEmpty == false
        )
    }

    static func extractDuration(
        selected sel: SelectedFmts
    ) -> Double? {
        let key = "approxDurationMs"
        let ms = (sel.video?[key] as? String)
            ?? (sel.audio?[key] as? String)
        return ms.flatMap(Double.init)
            .map { $0 / 1_000.0 }
    }

    static func logStreamingDataSummary(
        _ json: [String: Any]
    ) {
        if let sd = json["streamingData"]
            as? [String: Any] {
            let fc = (sd["formats"]
                as? [[String: Any]])?.count ?? 0
            let ac = (sd["adaptiveFormats"]
                as? [[String: Any]])?.count ?? 0
            AppLog.innertube(
                "streamingData found:"
                    + " formats=\(fc)"
                    + " adaptive=\(ac)"
            )
        } else {
            let ps = (json["playabilityStatus"]
                as? [String: Any])?["status"]
                ?? "nil"
            AppLog.innertube(
                "streamingData MISSING"
                    + " playabilityStatus: \(ps)"
            )
        }
    }

    static func logDashSelection(
        video: DashFormatInfo?,
        audio: DashFormatInfo?
    ) {
        if let dv = video {
            logDashFormat("video", dv)
        }
        if let da = audio {
            logDashFormat("audio", da)
        }
    }

    static func logDashFormat(
        _ label: String,
        _ df: DashFormatInfo
    ) {
        AppLog.innertube(
            "DASH \(label): itag=\(df.itag)"
                + " init=0-\(df.initRangeEnd)"
                + " index=\(df.indexRangeStart)"
                + "-\(df.indexRangeEnd)"
                + " clen=\(df.contentLength)"
                + " codecs=\(df.codecs)"
        )
    }
}

// MARK: - Supporting Types

extension InnertubeClient {
    struct SelectedFmts {
        let progressive: [String: Any]?
        let video: [String: Any]?
        let audio: [String: Any]?
    }

    struct PlayerCfg {
        let playbackConfig: String?
        let onesieConfig: String?
        let hasPlaybackConfig: Bool
    }

    struct PlaybackURLs {
        let hls: URL?
        let dash: URL?
        let progressive: URL?
        let video: URL?
        let audio: URL?
        let sabr: URL?
        var hasAny: Bool {
            hls != nil || dash != nil
                || progressive != nil
                || (video != nil && audio != nil)
                || sabr != nil
        }
    }

    static func extractWatchtimeURLs(
        _ json: [String: Any]
    ) -> WatchtimeURLs? {
        let pt = json["playbackTracking"]
            as? [String: Any]
        if pt == nil {
            let ps = (json["playabilityStatus"]
                as? [String: Any])?["status"]
                ?? "nil"
            AppLog.innertube(
                "watchtimeURLs: no playbackTracking"
                    + " playabilityStatus=\(ps)"
            )
        }
        guard let pbURL = (pt?["videostatsPlaybackUrl"]
            as? [String: Any])?["baseUrl"] as? String,
              let wtURL = (pt?["videostatsWatchtimeUrl"]
            as? [String: Any])?["baseUrl"] as? String
        else {
            return nil
        }
        let dur = extractDurationFromJSON(json)
        return WatchtimeURLs(
            playbackURL: pbURL,
            watchtimeURL: wtURL,
            duration: dur
        )
    }

    static func extractDurationFromJSON(
        _ json: [String: Any]
    ) -> Double? {
        let sd = json["streamingData"]
            as? [String: Any]
        let fmts = (sd?["formats"]
            as? [[String: Any]] ?? [])
            + (sd?["adaptiveFormats"]
                as? [[String: Any]] ?? [])
        return fmts
            .compactMap {
                ($0["approxDurationMs"] as? String)
                    .flatMap(Double.init)
            }
            .first
            .map { $0 / 1_000.0 }
    }
}
