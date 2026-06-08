import AVFoundation

// MARK: - AVAssetResourceLoaderDelegate

final class HLSPlaylistLoader: NSObject,
    AVAssetResourceLoaderDelegate {
    let loaderQueue = DispatchQueue(
        label: "com.ytvlite.hls-loader"
    )

    private var playlists: [String: Data] = [:]

    /// Register playlist content for a given path.
    func register(path: String, content: String) {
        playlists[path] = Data(content.utf8)
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource
        request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = request.request.url else {
            return false
        }
        AppLog.hls("request: \(url.absoluteString)")
        guard url.scheme == HLSGenerator.scheme else {
            let sch = url.scheme ?? "nil"
            AppLog.hls("non-custom scheme: \(sch)")
            return false
        }
        guard let key = resolvePlaylistKey(from: url) else {
            logUnknownPath(url)
            let err = NSError(
                domain: "HLSPlaylistLoader",
                code: -1,
                userInfo: nil
            )
            request.finishLoading(with: err)
            return true
        }
        guard let data = playlists[key] else {
            return false
        }
        AppLog.hls("serving \(key) (\(data.count) bytes)")
        fillLoadingRequest(request, with: data)
        request.finishLoading()
        return true
    }

    // MARK: - Private Helpers

    private func resolvePlaylistKey(
        from url: URL
    ) -> String? {
        if let host = url.host, playlists[host] != nil {
            return host
        }
        let trimmed = String(url.path.dropFirst())
        if playlists[trimmed] != nil {
            return trimmed
        }
        return nil
    }

    private func logUnknownPath(_ url: URL) {
        let host = url.host ?? "nil"
        let keys = Array(playlists.keys)
        AppLog.hls(
            "unknown: host=\(host)"
                + " path=\(url.path)"
                + " keys=\(keys)"
        )
    }

    private func fillLoadingRequest(
        _ request: AVAssetResourceLoadingRequest,
        with data: Data
    ) {
        if let info = request.contentInformationRequest {
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        if let dataReq = request.dataRequest {
            let off = Int(dataReq.requestedOffset)
            let len = responseLength(
                dataReq: dataReq,
                offset: off,
                dataCount: data.count
            )
            if off < data.count, len > 0 {
                let range = off..<(off + len)
                dataReq.respond(
                    with: data.subdata(in: range)
                )
            }
        }
    }

    private func responseLength(
        dataReq: AVAssetResourceLoadingDataRequest,
        offset: Int,
        dataCount: Int
    ) -> Int {
        if dataReq.requestsAllDataToEndOfResource {
            return dataCount - offset
        }
        return min(dataReq.requestedLength, dataCount - offset)
    }
}

// MARK: - Data Big-Endian Helpers

extension Data {
    func readBigUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else {
            return 0
        }
        return UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    func readBigUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else {
            return 0
        }
        let b0 = UInt64(self[offset]) << 56
        let b1 = UInt64(self[offset + 1]) << 48
        let b2 = UInt64(self[offset + 2]) << 40
        let b3 = UInt64(self[offset + 3]) << 32
        let b4 = UInt64(self[offset + 4]) << 24
        let b5 = UInt64(self[offset + 5]) << 16
        let b6 = UInt64(self[offset + 6]) << 8
        let b7 = UInt64(self[offset + 7])
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
    }

    func readFourCC(at offset: Int) -> String {
        guard offset + 4 <= count else {
            return ""
        }
        return String(
            bytes: self[offset..<offset + 4],
            encoding: .ascii
        ) ?? ""
    }
}
