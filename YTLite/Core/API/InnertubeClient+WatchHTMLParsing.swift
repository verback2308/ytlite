import Foundation

// MARK: - Watch-page HTML parsing

//
// The server-rendered watch page embeds `ytInitialPlayerResponse` — the same
// player JSON the Innertube API returns. Sources that resolve playback from
// the HTML (WebView HLS) reuse the regular response parsers on it.

extension InnertubeClient {
    /// Extracts caption tracks from a watch-page HTML document.
    static func extractCaptionTracks(fromWatchHTML html: String) -> [SubtitleTrack] {
        guard let json = playerResponseJSON(from: html) else {
            return []
        }
        return extractCaptionTracks(json)
    }

    /// Extracts caption tracks from a player-response JSON object.
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
        guard let raw = track["baseUrl"] as? String else {
            return nil
        }
        // The MWEB /player response returns baseUrl as a relative path;
        // URL(string:) accepts it but URLSession then fails with -1002.
        let absolute = raw.hasPrefix("/") ? AppURLs.YouTube.base + raw : raw
        guard let url = URL(string: absolute) else {
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

    private static func playerResponseJSON(from html: String) -> [String: Any]? {
        guard let range = html.range(of: "ytInitialPlayerResponse"),
              let upper = range.upperBound.samePosition(in: html.utf8)
        else {
            return nil
        }
        let offset = html.utf8.distance(from: html.utf8.startIndex, to: upper)
        guard let data = jsonObjectData(in: Array(html.utf8), from: offset) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Returns the bytes of the first balanced `{...}` object at or after
    /// `startSearch`, honoring string literals and escapes.
    private static func jsonObjectData(in bytes: [UInt8], from startSearch: Int) -> Data? {
        guard startSearch < bytes.count,
              let start = bytes[startSearch...].firstIndex(of: UInt8(ascii: "{"))
        else {
            return nil
        }
        var scanner = JSONObjectScanner()
        for idx in start ..< bytes.count where scanner.objectCloses(at: bytes[idx]) {
            return Data(bytes[start ... idx])
        }
        return nil
    }
}

/// Byte-level scanner state for balancing a JSON object's braces.
private struct JSONObjectScanner {
    private var depth = 0
    private var inString = false
    private var escaped = false

    /// Consumes one byte; true when the top-level object just closed.
    mutating func objectCloses(at byte: UInt8) -> Bool {
        if escaped {
            escaped = false
            return false
        }
        switch byte {
        case UInt8(ascii: "\\") where inString:
            escaped = true
        case UInt8(ascii: "\""):
            inString.toggle()
        case UInt8(ascii: "{") where !inString:
            depth += 1
        case UInt8(ascii: "}") where !inString:
            depth -= 1
            return depth == 0
        default:
            break
        }
        return false
    }
}
