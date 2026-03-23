import Foundation
import AVFoundation

/// Intercepts AVURLAsset loading to remap YouTube's moov-at-end mp4 files
/// into faststart layout (moov before mdat) for instant playback start.
///
/// YouTube adaptive streams (video-only / audio-only mp4) place the moov atom
/// at the end of the file. AVFoundation must download nearly the entire file
/// to find it, causing 20-40s delays. This loader fetches moov first via a
/// small Range request, adjusts chunk offsets, and presents a virtual file
/// with moov at the front — so AVPlayer starts streaming immediately.
final class FastStartResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "faststart"

    private let realURL: URL
    private let headers: [String: String]
    let loaderQueue = DispatchQueue(label: "com.ytvlite.faststart-loader")

    // Setup state
    private var fileSize: Int64 = 0
    private var isSettingUp = false
    private var isReady = false
    private var isFailed = false
    private var isPassthrough = false  // moov already at front — proxy directly

    // Remapped layout data
    private var prefixData: Data?       // ftyp (+ any small boxes before mdat)
    private var moovAdjusted: Data?     // moov with fixed stco/co64 offsets
    private var mdatOrigOffset: Int64 = 0
    private var virtualMoovOffset: Int64 = 0
    private var virtualMdatOffset: Int64 = 0
    private var virtualTotalSize: Int64 = 0

    private var pendingRequests: [AVAssetResourceLoadingRequest] = []

    init(realURL: URL, headers: [String: String]) {
        self.realURL = realURL
        self.headers = headers
        super.init()
    }

    /// Convert https://… to faststart://… for AVURLAsset
    static func customURL(from url: URL) -> URL? {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = scheme
        return c.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if isFailed { return false }
        if isPassthrough {
            handlePassthroughRequest(request)
            return true
        }
        if isReady {
            handleRequest(request)
            return true
        }
        pendingRequests.append(request)
        if !isSettingUp {
            isSettingUp = true
            performSetup()
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        pendingRequests.removeAll { $0 === loadingRequest }
    }

    // MARK: - Setup: fetch moov, determine layout, adjust offsets

    private func performSetup() {
        let startTime = CACurrentMediaTime()

        // HEAD to get Content-Length
        var headReq = URLRequest(url: realURL)
        headReq.httpMethod = "HEAD"
        applyHeaders(&headReq)

        URLSession.shared.dataTask(with: headReq) { [weak self] _, response, _ in
            guard let self = self,
                  let http = response as? HTTPURLResponse,
                  let cl = self.contentLength(from: http), cl > 1024 else {
                self?.failSetup("HEAD failed")
                return
            }
            self.fileSize = cl
            self.fetchLayout(startTime: startTime)
        }.resume()
    }

    private func fetchLayout(startTime: Double) {
        // Fetch first 4KB (ftyp + box headers) and last 2MB (moov) in parallel
        let headSize: Int64 = 4096
        let tailSize: Int64 = min(2 * 1024 * 1024, fileSize / 2)
        let tailStart = fileSize - tailSize
        let group = DispatchGroup()

        var headData: Data?
        var tailData: Data?

        group.enter()
        fetchRange(start: 0, length: headSize) { data in headData = data; group.leave() }

        group.enter()
        fetchRange(start: tailStart, length: tailSize) { data in tailData = data; group.leave() }

        group.notify(queue: loaderQueue) { [weak self] in
            guard let self = self, let headData = headData, let tailData = tailData else {
                self?.failSetup("fetch head/tail failed")
                return
            }
            self.parseAndBuild(headData: headData, tailData: tailData, tailStart: tailStart, startTime: startTime)
        }
    }

    private func parseAndBuild(headData: Data, tailData: Data, tailStart: Int64, startTime: Double) {
        // Parse top-level boxes from head to find mdat offset
        var mdatOffset: Int64 = -1
        var pos: Int = 0

        while pos + 8 <= headData.count {
            let boxSize = Int64(headData.readBigUInt32(at: pos))
            let boxType = headData.readFourCC(at: pos + 4)
            guard boxSize >= 8 else { break }

            if boxType == "moov" {
                // moov is before mdat — already faststart, use passthrough
                print("[FastStartLoader] moov already at front — passthrough mode")
                isPassthrough = true
                isSettingUp = false
                processPassthroughPending()
                return
            }
            if boxType == "mdat" {
                mdatOffset = Int64(pos)
                break
            }
            pos += Int(boxSize)
        }

        guard mdatOffset >= 0 else {
            failSetup("mdat not found in first 4KB")
            return
        }

        // Find moov in tail data
        var moovRelOffset: Int = -1
        var moovSize: Int64 = 0
        var scanPos = 0

        while scanPos + 8 <= tailData.count {
            let boxSize = Int64(tailData.readBigUInt32(at: scanPos))
            let boxType = tailData.readFourCC(at: scanPos + 4)
            guard boxSize >= 8 else { scanPos += 1; continue }

            if boxType == "moov" {
                moovRelOffset = scanPos
                moovSize = boxSize
                break
            }
            if scanPos + Int(boxSize) > tailData.count { break }
            scanPos += Int(boxSize)
        }

        guard moovRelOffset >= 0, moovSize > 0 else {
            failSetup("moov not found in tail")
            return
        }

        let moovAbsOffset = tailStart + Int64(moovRelOffset)
        let mdatSize = moovAbsOffset - mdatOffset

        // Extract and adjust moov
        let moovEnd = moovRelOffset + Int(moovSize)
        guard moovEnd <= tailData.count else {
            failSetup("moov extends beyond fetched tail")
            return
        }
        var adjustedMoov = tailData.subdata(in: moovRelOffset..<moovEnd)
        FastStartResourceLoader.adjustChunkOffsets(in: &adjustedMoov, delta: moovSize)

        // Build prefix (everything before mdat)
        let prefixSize = Int(mdatOffset)
        let prefix: Data
        if prefixSize <= headData.count {
            prefix = headData.subdata(in: 0..<prefixSize)
        } else {
            // Unusual — more boxes before mdat than 4KB; just use what we have
            prefix = headData
        }

        // Virtual layout: [prefix][moov'][mdat]
        self.prefixData = prefix
        self.moovAdjusted = adjustedMoov
        self.mdatOrigOffset = mdatOffset
        self.virtualMoovOffset = Int64(prefix.count)
        self.virtualMdatOffset = Int64(prefix.count) + moovSize
        self.virtualTotalSize = Int64(prefix.count) + moovSize + mdatSize

        let elapsed = CACurrentMediaTime() - startTime
        print(String(format: "[FastStartLoader] ready in %.1fs: moov=%lld bytes, mdat=%lld bytes, virtual=%lld bytes",
                     elapsed, moovSize, mdatSize, virtualTotalSize))

        isReady = true
        isSettingUp = false
        processPendingRequests()
    }

    // MARK: - Serve data requests

    private func handleRequest(_ request: AVAssetResourceLoadingRequest) {
        if let info = request.contentInformationRequest {
            info.contentType = "public.mpeg-4"
            info.contentLength = virtualTotalSize
            info.isByteRangeAccessSupported = true
        }

        guard let dataReq = request.dataRequest else {
            request.finishLoading()
            return
        }

        let reqOffset = dataReq.requestedOffset
        let reqLength: Int64
        if dataReq.requestsAllDataToEndOfResource {
            reqLength = virtualTotalSize - reqOffset
        } else {
            reqLength = Int64(dataReq.requestedLength)
        }
        let reqEnd = reqOffset + reqLength

        // Serve in-memory regions (prefix + moov)
        var virtualPos = reqOffset

        if virtualPos < virtualMoovOffset, let prefix = prefixData {
            let start = Int(virtualPos)
            let end = min(Int(min(reqEnd, virtualMoovOffset)), prefix.count)
            if start < end {
                dataReq.respond(with: prefix.subdata(in: start..<end))
                virtualPos = Int64(end)
            }
        }

        if virtualPos >= virtualMoovOffset && virtualPos < virtualMdatOffset, let moov = moovAdjusted {
            let start = Int(virtualPos - virtualMoovOffset)
            let end = min(Int(reqEnd - virtualMoovOffset), moov.count)
            if start < end {
                dataReq.respond(with: moov.subdata(in: start..<end))
                virtualPos = virtualMoovOffset + Int64(end)
            }
        }

        // Mdat region — proxy from YouTube via Range request
        if virtualPos >= virtualMdatOffset && virtualPos < reqEnd {
            let realOffset = mdatOrigOffset + (virtualPos - virtualMdatOffset)
            let realLength = reqEnd - virtualPos

            fetchRange(start: realOffset, length: realLength) { data in
                if let data = data, !data.isEmpty {
                    dataReq.respond(with: data)
                }
                request.finishLoading()
            }
        } else {
            request.finishLoading()
        }
    }

    // MARK: - stco / co64 offset adjustment

    /// Adjusts all stco/co64 chunk offsets inside moov by `delta` bytes.
    static func adjustChunkOffsets(in data: inout Data, delta: Int64) {
        guard data.count > 8 else { return }
        walkBoxes(in: &data, range: 8..<data.count, delta: delta)
    }

    private static let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "udta", "meta"]

    private static func walkBoxes(in data: inout Data, range: Range<Int>, delta: Int64) {
        var pos = range.lowerBound
        while pos + 8 <= range.upperBound {
            let boxSize = Int(data.readBigUInt32(at: pos))
            let boxType = data.readFourCC(at: pos + 4)
            guard boxSize >= 8, pos + boxSize <= range.upperBound else { break }

            if containerTypes.contains(boxType) {
                let headerSize = (boxType == "meta") ? 12 : 8  // meta has version+flags
                walkBoxes(in: &data, range: (pos + headerSize)..<(pos + boxSize), delta: delta)
            } else if boxType == "stco" {
                let count = Int(data.readBigUInt32(at: pos + 12))
                for i in 0..<count {
                    let off = pos + 16 + i * 4
                    guard off + 4 <= pos + boxSize else { break }
                    let old = Int64(data.readBigUInt32(at: off))
                    data.writeBigUInt32(UInt32(clamping: old + delta), at: off)
                }
            } else if boxType == "co64" {
                let count = Int(data.readBigUInt32(at: pos + 12))
                for i in 0..<count {
                    let off = pos + 16 + i * 8
                    guard off + 8 <= pos + boxSize else { break }
                    let old = Int64(bitPattern: data.readBigUInt64(at: off))
                    data.writeBigUInt64(UInt64(bitPattern: old + delta), at: off)
                }
            }
            pos += boxSize
        }
    }

    // MARK: - Passthrough mode (moov already at front)

    private func handlePassthroughRequest(_ request: AVAssetResourceLoadingRequest) {
        if let info = request.contentInformationRequest {
            info.contentType = "public.mpeg-4"
            info.contentLength = fileSize
            info.isByteRangeAccessSupported = true
        }

        guard let dataReq = request.dataRequest else {
            request.finishLoading()
            return
        }

        let offset = dataReq.requestedOffset
        let length: Int64
        if dataReq.requestsAllDataToEndOfResource {
            length = fileSize - offset
        } else {
            length = Int64(dataReq.requestedLength)
        }

        fetchRange(start: offset, length: length) { data in
            if let data = data, !data.isEmpty {
                dataReq.respond(with: data)
            }
            request.finishLoading()
        }
    }

    private func processPassthroughPending() {
        let reqs = pendingRequests
        pendingRequests.removeAll()
        for r in reqs { handlePassthroughRequest(r) }
    }

    // MARK: - Helpers

    private func applyHeaders(_ request: inout URLRequest) {
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    }

    private func contentLength(from response: HTTPURLResponse) -> Int64? {
        if let s = response.allHeaderFields["Content-Length"] as? String { return Int64(s) }
        return nil
    }

    private func fetchRange(start: Int64, length: Int64, completion: @escaping (Data?) -> Void) {
        var req = URLRequest(url: realURL)
        applyHeaders(&req)
        req.setValue("bytes=\(start)-\(start + length - 1)", forHTTPHeaderField: "Range")
        URLSession.shared.dataTask(with: req) { data, _, _ in completion(data) }.resume()
    }

    private func failSetup(_ reason: String) {
        print("[FastStartLoader] setup failed: \(reason)")
        isFailed = true
        isSettingUp = false
        let reqs = pendingRequests
        pendingRequests.removeAll()
        for r in reqs { r.finishLoading(with: NSError(domain: "FastStartLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])) }
    }

    private func processPendingRequests() {
        let reqs = pendingRequests
        pendingRequests.removeAll()
        for r in reqs { handleRequest(r) }
    }
}

// MARK: - Data extensions for big-endian integer I/O

extension Data {
    func readBigUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        var v: UInt32 = 0
        _ = withUnsafeBytes { memcpy(&v, $0.baseAddress! + offset, 4) }
        return UInt32(bigEndian: v)
    }

    func readBigUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        var v: UInt64 = 0
        _ = withUnsafeBytes { memcpy(&v, $0.baseAddress! + offset, 8) }
        return UInt64(bigEndian: v)
    }

    func readFourCC(at offset: Int) -> String {
        guard offset + 4 <= count else { return "" }
        return String(bytes: self[offset..<offset + 4], encoding: .ascii) ?? ""
    }

    mutating func writeBigUInt32(_ value: UInt32, at offset: Int) {
        guard offset + 4 <= count else { return }
        var v = value.bigEndian
        _ = withUnsafeMutableBytes { memcpy($0.baseAddress! + offset, &v, 4) }
    }

    mutating func writeBigUInt64(_ value: UInt64, at offset: Int) {
        guard offset + 8 <= count else { return }
        var v = value.bigEndian
        _ = withUnsafeMutableBytes { memcpy($0.baseAddress! + offset, &v, 8) }
    }
}
