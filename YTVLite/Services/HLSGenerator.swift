import Foundation
import AVFoundation

struct SidxSegment {
    let offset: Int64
    let size: Int64
    let duration: Double
}

enum HLSGenerator {
    // MARK: - Subtypes

    struct PlaylistURIs {
        let video: String
        let audio: String
    }

    private struct SidxHeader {
        let timescale: UInt32
        let referenceCount: Int
        let referencesStart: Int
    }

    // MARK: - Properties

    static let scheme = "ytv-hls"

    // MARK: - sidx parsing

    /// Parse a sidx box from raw data.
    static func parseSidx(data: Data) -> [SidxSegment]? {
        var pos = 0
        while pos + 8 <= data.count {
            var boxSize = Int64(data.readBigUInt32(at: pos))
            let boxType = data.readFourCC(at: pos + 4)
            if boxSize == 1, pos + 16 <= data.count {
                boxSize = Int64(
                    bitPattern: data.readBigUInt64(at: pos + 8)
                )
            }
            guard boxSize >= 8 else { break }
            if boxType == "sidx" {
                let clamped = Int(
                    min(boxSize, Int64(data.count - pos))
                )
                return parseSidxContent(
                    data: data,
                    boxStart: pos,
                    boxSize: clamped
                )
            }
            pos += Int(boxSize)
        }
        return nil
    }

    private static func parseSidxHeader(
        data: Data,
        boxStart: Int,
        boxEnd: Int
    ) -> SidxHeader? {
        var pos = boxStart + 8
        guard pos + 4 <= boxEnd else {
            return nil
        }
        let version = data[pos]
        pos += 4
        guard pos + 8 <= boxEnd else {
            return nil
        }
        let timescale = data.readBigUInt32(at: pos + 4)
        guard timescale > 0 else {
            return nil
        }
        pos += 8
        let timeFieldSize = version == 0 ? 8 : 16
        guard pos + timeFieldSize <= boxEnd else {
            return nil
        }
        pos += timeFieldSize
        guard pos + 4 <= boxEnd else {
            return nil
        }
        pos += 2
        let refCount = Int(readBigUInt16(data: data, at: pos))
        pos += 2
        return SidxHeader(
            timescale: timescale,
            referenceCount: refCount,
            referencesStart: pos
        )
    }

    private static func parseSidxContent(
        data: Data,
        boxStart: Int,
        boxSize: Int
    ) -> [SidxSegment]? {
        let boxEnd = boxStart + boxSize
        guard let header = parseSidxHeader(
            data: data,
            boxStart: boxStart,
            boxEnd: boxEnd
        ) else {
            return nil
        }
        var segments: [SidxSegment] = []
        segments.reserveCapacity(header.referenceCount)
        var currentOffset: Int64 = 0
        var pos = header.referencesStart
        for _ in 0..<header.referenceCount {
            guard pos + 12 <= boxEnd else { break }
            let refWord = data.readBigUInt32(at: pos)
            let refSize = Int64(refWord & 0x7FFF_FFFF)
            pos += 4
            let subDur = data.readBigUInt32(at: pos)
            pos += 8
            let dur = Double(subDur) / Double(header.timescale)
            segments.append(SidxSegment(
                offset: currentOffset,
                size: refSize,
                duration: dur
            ))
            currentOffset += refSize
        }
        return segments.isEmpty ? nil : segments
    }

    // MARK: - HLS playlist generation

    /// Generate a media playlist with byte-range segments.
    static func mediaPlaylist(
        url: URL,
        initBytes: Int,
        dataStartOffset: Int64,
        segments: [SidxSegment]
    ) -> String {
        let maxDur = segments.map(\.duration).max() ?? 5
        let urlStr = url.absoluteString
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        let target = Int(ceil(maxDur))
        lines.append("#EXT-X-TARGETDURATION:\(target)")
        lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        let mapTag = "#EXT-X-MAP:URI=\"\(urlStr)\""
            + ",BYTERANGE=\"\(initBytes)@0\""
        lines.append(mapTag)
        for segment in segments {
            let off = dataStartOffset + segment.offset
            let inf = String(
                format: "#EXTINF:%.3f,",
                segment.duration
            )
            lines.append(inf)
            lines.append(
                "#EXT-X-BYTERANGE:\(segment.size)@\(off)"
            )
            lines.append(urlStr)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate an audio-only main playlist.
    static func audioOnlyMainPlaylist(
        audioCodecs: String,
        audioBandwidth: Int,
        audioPlaylistURI: String
    ) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        let streamInf = "#EXT-X-STREAM-INF:"
            + "BANDWIDTH=\(audioBandwidth)"
            + ",CODECS=\"\(audioCodecs)\""
        lines.append(streamInf)
        lines.append(audioPlaylistURI)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate a main playlist with video and audio.
    static func mainPlaylist(
        bandwidth: Int,
        codecs: String,
        resolution: String,
        uris: PlaylistURIs
    ) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        let mediaTag = "#EXT-X-MEDIA:TYPE=AUDIO"
            + ",GROUP-ID=\"audio\",NAME=\"Main\""
            + ",DEFAULT=YES,AUTOSELECT=YES"
            + ",URI=\"\(uris.audio)\""
        lines.append(mediaTag)
        let streamInf = "#EXT-X-STREAM-INF:"
            + "BANDWIDTH=\(bandwidth)"
            + ",CODECS=\"\(codecs)\""
            + ",RESOLUTION=\(resolution)"
            + ",AUDIO=\"audio\""
        lines.append(streamInf)
        lines.append(uris.video)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func readBigUInt16(
        data: Data,
        at offset: Int
    ) -> UInt16 {
        guard offset + 2 <= data.count else {
            return 0
        }
        return UInt16(data[offset]) << 8
            | UInt16(data[offset + 1])
    }
}
