import Foundation

/// One video variant from a live HLS multivariant (main) playlist.
struct LiveHLSVariant: Equatable {
    let quality: VideoQuality
    /// Absolute media-playlist URL — doubles as the quality id.
    let uri: String
}

/// Parses live HLS multivariant playlists into selectable variants and filters
/// a playlist down to a single variant, so a `VideoSource` can pin a fixed
/// live quality instead of leaving AVPlayer's ABR to sit on a low rung.
enum LiveHLSVariants {
    static func parse(playlist: String, baseURL: URL) -> [LiveHLSVariant] {
        var variants: [LiveHLSVariant] = []
        var pendingInf: String?
        for raw in playlist.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingInf = line
            } else if let inf = pendingInf, isURILine(line) {
                if let variant = makeVariant(inf: inf, uri: line, baseURL: baseURL) {
                    variants.append(variant)
                }
                pendingInf = nil
            }
        }
        return dedupedSorted(variants)
    }

    /// Rewrites the playlist keeping only `variant`'s `#EXT-X-STREAM-INF`
    /// entry; every other line (headers, media groups) is preserved. The kept
    /// URI is absolutized so the result can be served from a custom-scheme
    /// loader.
    static func manifest(
        keeping variant: LiveHLSVariant, playlist: String, baseURL: URL
    ) -> String {
        var lines: [String] = []
        var pendingInf: String?
        for raw in playlist.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingInf = line
            } else if let inf = pendingInf, isURILine(line) {
                if URL(string: line, relativeTo: baseURL)?.absoluteString == variant.uri {
                    lines.append(inf)
                    lines.append(variant.uri)
                }
                pendingInf = nil
            } else if pendingInf == nil {
                lines.append(raw)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func isURILine(_ line: String) -> Bool {
        !line.isEmpty && !line.hasPrefix("#")
    }

    private static func makeVariant(
        inf: String, uri: String, baseURL: URL
    ) -> LiveHLSVariant? {
        let height = HLSStreamResolver.firstMatch(
            in: inf, pattern: "RESOLUTION=\\d+x(\\d+)"
        )
        guard let url = URL(string: uri, relativeTo: baseURL),
              let height = height.flatMap(Int.init)
        else {
            return nil
        }
        let rate = HLSStreamResolver.firstMatch(in: inf, pattern: "FRAME-RATE=([\\d.]+)")
        let fps = rate.flatMap(Double.init).map { Int($0.rounded()) }
        let label = (fps ?? 0) > 30 ? "\(height)p\(fps ?? 0)" : "\(height)p"
        let absolute = url.absoluteString
        return LiveHLSVariant(
            quality: VideoQuality(id: absolute, label: label, height: height, fps: fps),
            uri: absolute
        )
    }

    private static func dedupedSorted(_ variants: [LiveHLSVariant]) -> [LiveHLSVariant] {
        var seenLabels = Set<String>()
        return variants
            .sorted { lhs, rhs in
                let lh = lhs.quality.height ?? 0
                let rh = rhs.quality.height ?? 0
                if lh == rh {
                    return (lhs.quality.fps ?? 0) > (rhs.quality.fps ?? 0)
                }
                return lh > rh
            }
            .filter { seenLabels.insert($0.quality.label).inserted }
    }
}
