import Foundation
import AVFoundation

struct SidxSegment {
    let offset: Int64   // byte offset from data start (after sidx box)
    let size: Int64     // byte size of subsegment
    let duration: Double // duration in seconds
}

enum HLSGenerator {

    static let scheme = "ytv-hls"

    // MARK: - sidx parsing

    /// Parse a sidx box from raw data. Returns segment entries or nil on failure.
    static func parseSidx(data: Data) -> [SidxSegment]? {
        var pos = 0
        while pos + 8 <= data.count {
            var boxSize = Int64(data.readBigUInt32(at: pos))
            let boxType = data.readFourCC(at: pos + 4)
            if boxSize == 1, pos + 16 <= data.count {
                boxSize = Int64(bitPattern: data.readBigUInt64(at: pos + 8))
            }
            guard boxSize >= 8 else { break }

            if boxType == "sidx" {
                return parseSidxContent(data: data, boxStart: pos, boxSize: Int(min(boxSize, Int64(data.count - pos))))
            }
            pos += Int(boxSize)
        }
        return nil
    }

    private static func parseSidxContent(data: Data, boxStart: Int, boxSize: Int) -> [SidxSegment]? {
        var pos = boxStart + 8 // skip size + type
        guard pos + 4 <= boxStart + boxSize else { return nil }

        let version = data[pos]
        pos += 4 // version (1) + flags (3)

        guard pos + 8 <= boxStart + boxSize else { return nil }
        pos += 4 // reference_ID
        let timescale = data.readBigUInt32(at: pos)
        guard timescale > 0 else { return nil }
        pos += 4

        if version == 0 {
            guard pos + 8 <= boxStart + boxSize else { return nil }
            pos += 4 // earliest_presentation_time
            pos += 4 // first_offset
        } else {
            guard pos + 16 <= boxStart + boxSize else { return nil }
            pos += 8 // earliest_presentation_time (64-bit)
            pos += 8 // first_offset (64-bit)
        }

        guard pos + 4 <= boxStart + boxSize else { return nil }
        pos += 2 // reserved
        let referenceCount = Int(readBigUInt16(data: data, at: pos))
        pos += 2

        var segments: [SidxSegment] = []
        segments.reserveCapacity(referenceCount)
        var currentOffset: Int64 = 0

        for _ in 0..<referenceCount {
            guard pos + 12 <= boxStart + boxSize else { break }

            let refWord = data.readBigUInt32(at: pos)
            let referencedSize = Int64(refWord & 0x7FFFFFFF)
            pos += 4

            let subsegmentDuration = data.readBigUInt32(at: pos)
            pos += 4

            pos += 4 // SAP info

            let duration = Double(subsegmentDuration) / Double(timescale)
            segments.append(SidxSegment(offset: currentOffset, size: referencedSize, duration: duration))
            currentOffset += referencedSize
        }

        return segments.isEmpty ? nil : segments
    }

    // MARK: - HLS playlist generation

    /// Generate a media playlist (video or audio) with byte-range segments.
    static func mediaPlaylist(url: URL, initBytes: Int, dataStartOffset: Int64, segments: [SidxSegment]) -> String {
        let maxDuration = segments.map { $0.duration }.max() ?? 5
        let urlString = url.absoluteString

        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-TARGETDURATION:\(Int(ceil(maxDuration)))")
        lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        lines.append("#EXT-X-MAP:URI=\"\(urlString)\",BYTERANGE=\"\(initBytes)@0\"")

        for segment in segments {
            let byteOffset = dataStartOffset + segment.offset
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append("#EXT-X-BYTERANGE:\(segment.size)@\(byteOffset)")
            lines.append(urlString)
        }

        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate an audio-only master playlist for background playback.
    static func audioOnlyMasterPlaylist(audioCodecs: String, audioBandwidth: Int, audioPlaylistURI: String) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        lines.append("#EXT-X-STREAM-INF:BANDWIDTH=\(audioBandwidth),CODECS=\"\(audioCodecs)\"")
        lines.append(audioPlaylistURI)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate a master playlist with separate video and audio renditions.
    /// Playlist filenames must be absolute URIs (e.g. "ytv-hls://video.m3u8").
    static func masterPlaylist(videoBandwidth: Int, videoCodecs: String, audioCodecs: String,
                               width: Int, height: Int,
                               videoPlaylistURI: String, audioPlaylistURI: String) -> String {
        let combinedCodecs = "\(videoCodecs),\(audioCodecs)"
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        lines.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"Main\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioPlaylistURI)\"")
        lines.append("#EXT-X-STREAM-INF:BANDWIDTH=\(videoBandwidth),CODECS=\"\(combinedCodecs)\",RESOLUTION=\(width)x\(height),AUDIO=\"audio\"")
        lines.append(videoPlaylistURI)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func readBigUInt16(data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}

// MARK: - AVAssetResourceLoaderDelegate for serving HLS playlists from memory

final class HLSPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate {

    let loaderQueue = DispatchQueue(label: "com.ytvlite.hls-loader")

    private var playlists: [String: Data] = [:] // path → playlist data

    /// Register playlist content for a given path (e.g. "master.m3u8", "video.m3u8")
    func register(path: String, content: String) {
        playlists[path] = Data(content.utf8)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url else { return false }

        print("[HLSPlaylistLoader] request: \(url.absoluteString)")

        guard url.scheme == HLSGenerator.scheme else {
            print("[HLSPlaylistLoader] non-custom scheme, declining: \(url.scheme ?? "nil")")
            return false
        }

        // "ytv-hls://master.m3u8" → host="master.m3u8", path=""
        // "ytv-hls:///video.m3u8" → host=nil, path="/video.m3u8"
        let key: String
        if let host = url.host, playlists[host] != nil {
            key = host
        } else {
            let trimmed = String(url.path.dropFirst()) // remove leading /
            if playlists[trimmed] != nil {
                key = trimmed
            } else {
                print("[HLSPlaylistLoader] unknown path: host=\(url.host ?? "nil") path=\(url.path) keys=\(Array(playlists.keys))")
                request.finishLoading(with: NSError(domain: "HLSPlaylistLoader", code: -1, userInfo: nil))
                return true
            }
        }

        let data = playlists[key]!
        print("[HLSPlaylistLoader] serving \(key) (\(data.count) bytes)")

        if let info = request.contentInformationRequest {
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }

        if let dataReq = request.dataRequest {
            let offset = Int(dataReq.requestedOffset)
            let length: Int
            if dataReq.requestsAllDataToEndOfResource {
                length = data.count - offset
            } else {
                length = min(dataReq.requestedLength, data.count - offset)
            }
            if offset < data.count && length > 0 {
                dataReq.respond(with: data.subdata(in: offset..<(offset + length)))
            }
        }

        request.finishLoading()
        return true
    }
}
