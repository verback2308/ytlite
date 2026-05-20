import Foundation

extension InnertubeClient {
    static func logPlayerDebug(
        videoId: String,
        contextName ctx: String,
        json: [String: Any]
    ) {
        let sd = json["streamingData"]
            as? [String: Any]
        let fmts = sd?["formats"]
            as? [[String: Any]] ?? []
        let adFmts = sd?["adaptiveFormats"]
            as? [[String: Any]] ?? []
        logManifests(
            vid: videoId,
            ctx: ctx,
            json: json
        )
        logFormats(
            ctx: ctx,
            formats: fmts,
            adaptive: adFmts
        )
        if ctx == "TVHTML5" {
            logDirectPlaybackCandidates(
                videoId: videoId,
                formats: fmts,
                adaptiveFormats: adFmts
            )
        }
    }

    static func logDirectPlaybackCandidates(
        videoId: String,
        formats: [[String: Any]],
        adaptiveFormats: [[String: Any]]
    ) {
        let prog = formats
            .filter { fmtURLString($0) != nil }
            .sorted {
                fmtBitrate($0) > fmtBitrate($1)
            }
        let vCands = filterVideoCandidates(
            adaptiveFormats
        )
        let aCands = filterAudioCandidates(
            adaptiveFormats
        )
        logProgCandidate(
            vid: videoId, prog: prog
        )
        logCandSummaries(
            vid: videoId,
            vCands: vCands,
            aCands: aCands
        )
    }

    /// Dumps raw JSON to ~/Documents/YTLite_channel_<name>.json for debugging.
    static func dumpChannelTabJSON(
        _ json: [String: Any],
        label: String
    ) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        let safe = label
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let fileName = "YTLite_channel_\(safe).json"
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        try? data.write(to: url)
        AppLog.innertube("JSON dump → \(url.path)")
    }
}

// MARK: - Private Helpers

private extension InnertubeClient {
    static func logManifests(
        vid: String,
        ctx: String,
        json: [String: Any]
    ) {
        let play = json["playabilityStatus"]
            as? [String: Any]
        let status = play?["status"]
            as? String ?? "nil"
        let reason = play?["reason"]
            as? String ?? "nil"
        let sd = json["streamingData"]
            as? [String: Any]
        let hls = sd?["hlsManifestUrl"]
            as? String ?? "nil"
        let dash = sd?["dashManifestUrl"]
            as? String ?? "nil"
        let sabr = sd?["serverAbrStreamingUrl"]
            as? String ?? "nil"
        AppLog.innertube(
            "player debug (\(ctx)) \(vid):"
                + " status=\(status),"
                + " reason=\(reason)"
        )
        AppLog.innertube(
            "player debug (\(ctx)) manifests:"
                + " hls=\(hls),"
                + " dash=\(dash),"
                + " sabr=\(sabr)"
        )
    }

    static func logFormats(
        ctx: String,
        formats: [[String: Any]],
        adaptive: [[String: Any]]
    ) {
        let fSum = formats.prefix(3)
            .map(summarizeFmt)
            .joined(separator: " | ")
        let aSum = adaptive.prefix(5)
            .map(summarizeFmt)
            .joined(separator: " | ")
        AppLog.innertube(
            "player debug (\(ctx))"
                + " formats=\(formats.count)"
                + " [\(fSum)]"
        )
        AppLog.innertube(
            "player debug (\(ctx))"
                + " adaptive=\(adaptive.count)"
                + " [\(aSum)]"
        )
    }

    static func summarizeFmt(
        _ fmt: [String: Any]
    ) -> String {
        let itag = fmt["itag"] as? Int ?? -1
        let mime = fmt["mimeType"]
            as? String ?? "nil"
        let hasURL = (fmt["url"] as? String)?
            .isEmpty == false
        let sc = fmt["signatureCipher"]
            as? String
        let ci = fmt["cipher"] as? String
        let hasCipher =
            sc?.isEmpty == false
            || ci?.isEmpty == false
        let quality = (fmt["qualityLabel"]
            as? String)
            ?? (fmt["audioQuality"]
                as? String) ?? "nil"
        return "itag=\(itag),"
            + " quality=\(quality),"
            + " mime=\(mime),"
            + " url=\(hasURL),"
            + " cipher=\(hasCipher)"
    }

    static func filterVideoCandidates(
        _ adaptiveFormats: [[String: Any]]
    ) -> [[String: Any]] {
        adaptiveFormats
            .filter {
                fmtURLString($0) != nil
                    && fmtMimeType($0)
                        .contains("video/mp4")
                    && fmtMimeType($0)
                        .contains("avc1")
            }
            .sorted {
                !heightBitrateLess($0, $1)
            }
    }

    static func filterAudioCandidates(
        _ adaptiveFormats: [[String: Any]]
    ) -> [[String: Any]] {
        adaptiveFormats
            .filter {
                fmtURLString($0) != nil
                    && fmtMimeType($0)
                        .contains("audio/mp4")
            }
            .sorted {
                fmtBitrate($0) > fmtBitrate($1)
            }
    }

    static func logProgCandidate(
        vid: String,
        prog: [[String: Any]]
    ) {
        if let best = prog.first,
           let url = fmtURLString(best) {
            let ql = best["qualityLabel"]
                as? String ?? "nil"
            let tag = best["itag"] as? Int ?? -1
            AppLog.innertube(
                "player direct (\(vid))"
                    + " progressive:"
                    + " itag=\(tag),"
                    + " quality=\(ql),"
                    + " mime=\(fmtMimeType(best)),"
                    + " bitrate=\(fmtBitrate(best)),"
                    + " url=\(url)"
            )
        } else {
            AppLog.innertube(
                "player direct (\(vid))"
                    + " progressive: none"
            )
        }
    }

    static func logCandSummaries(
        vid: String,
        vCands: [[String: Any]],
        aCands: [[String: Any]]
    ) {
        let vSum = vCands.prefix(3)
            .map { candSum($0, "qualityLabel") }
            .joined(separator: " | ")
        let aSum = aCands.prefix(3)
            .map { candSum($0, "audioQuality") }
            .joined(separator: " | ")
        AppLog.innertube(
            "player direct (\(vid))"
                + " mp4 video candidates:"
                + " \(vCands.count)"
                + " [\(vSum)]"
        )
        AppLog.innertube(
            "player direct (\(vid))"
                + " mp4 audio candidates:"
                + " \(aCands.count)"
                + " [\(aSum)]"
        )
        logSelectedCands(
            vid: vid,
            vCands: vCands,
            aCands: aCands
        )
    }

    static func candSum(
        _ fmt: [String: Any],
        _ key: String
    ) -> String {
        let ql = fmt[key] as? String ?? "nil"
        let tag = fmt["itag"] as? Int ?? -1
        return "itag=\(tag),"
            + " \(key)=\(ql),"
            + " bitrate=\(fmtBitrate(fmt)),"
            + " mime=\(fmtMimeType(fmt))"
    }

    static func logSelectedCands(
        vid: String,
        vCands: [[String: Any]],
        aCands: [[String: Any]]
    ) {
        guard let bv = vCands.first,
              let ba = aCands.first,
              let vURL = fmtURLString(bv),
              let aURL = fmtURLString(ba)
        else {
            return
        }
        let vq = bv["qualityLabel"]
            as? String ?? "nil"
        let aq = ba["audioQuality"]
            as? String ?? "nil"
        let vt = bv["itag"] as? Int ?? -1
        let at = ba["itag"] as? Int ?? -1
        AppLog.innertube(
            "player direct (\(vid))"
                + " selected video:"
                + " itag=\(vt),"
                + " quality=\(vq),"
                + " url=\(vURL)"
        )
        AppLog.innertube(
            "player direct (\(vid))"
                + " selected audio:"
                + " itag=\(at),"
                + " quality=\(aq),"
                    + " url=\(aURL)"
            )
        }
    }
