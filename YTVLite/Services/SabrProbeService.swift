import Compression
import Foundation

struct SabrProbeRequest {
    enum Mode {
        case startup
        case current
    }

    enum BootstrapStyle: String {
        case tokenField4
        case cookieField3
    }

    enum BootstrapHeaderPlacement: String {
        case field11
        case field3
    }

    enum TransportProfile: String {
        case tvHTML5
        case tvHTML5Brotli
        case tvHTML5Bare
        case tvHTML5BareBrotli
        case iosApp
        case iosAppBrotli

        var usesBrotliBody: Bool {
            self == .iosAppBrotli || self == .tvHTML5BareBrotli || self == .tvHTML5Brotli
        }

        var queryClientValue: String? {
            switch self {
            case .tvHTML5, .tvHTML5Brotli, .tvHTML5Bare, .tvHTML5BareBrotli:
                return nil
            case .iosApp, .iosAppBrotli:
                return "IOS"
            }
        }
    }

    enum BodyProfile: String {
        case lean
        case richAbrState
        case richStartup
    }

    let streamingURL: URL
    let ustreamerConfigData: Data
    let contentPoToken: String
    let client: DirectPlaybackClient
    let visitorData: String?
    let audioFormat: SabrFormatInfo
    let videoFormat: SabrFormatInfo
    let bootstrapParts: [OnesieResponsePart]
    let currentFormat: SabrFormatInfo?
    let mode: Mode
    let label: String
    let requestNumber: String
    let contentPlaybackNonce: String
    let bootstrapStyle: BootstrapStyle
    let includeBootstrapHeaders: Bool
    let transportProfile: TransportProfile
    let bootstrapHeaderPlacement: BootstrapHeaderPlacement
    let bodyProfile: BodyProfile
    let playbackCookie: Data?
    let activeSabrContexts: [SabrContextState]
    let unsentSabrContextTypes: [Int]
}

struct SabrProbeResult {
    let statusCode: Int
    let contentType: String?
    let bodySize: Int
    let bodyPrefixHex: String
    let umpPartTypes: [Int]
}

final class SabrProbeService {
    static let shared = SabrProbeService()

    private init() {}

    func buildStartupRequest(from request: SabrProbeRequest) -> URLRequest? {
        guard let poTokenData = Self.decodeWebSafeBase64(request.contentPoToken)
        else {
            return nil
        }

        let payload = Self.buildRequestBody(
            ustreamerConfig: request.ustreamerConfigData,
            poToken: poTokenData,
            client: request.client,
            transportProfile: request.transportProfile,
            audioFormat: request.audioFormat,
            videoFormat: request.videoFormat,
            bootstrapParts: request.bootstrapParts,
            currentFormat: request.currentFormat,
            mode: request.mode,
            bootstrapStyle: request.bootstrapStyle,
            includeBootstrapHeaders: request.includeBootstrapHeaders,
            bootstrapHeaderPlacement: request.bootstrapHeaderPlacement,
            bodyProfile: request.bodyProfile,
            playbackCookie: request.playbackCookie,
            activeSabrContexts: request.activeSabrContexts,
            unsentSabrContextTypes: request.unsentSabrContextTypes
        )
        let requestBody = request.transportProfile.usesBrotliBody ? (Self.brotliCompress(payload) ?? payload) : payload
        let bootstrapTokenLength = Self.extractBootstrapToken(from: request.bootstrapParts)?.count ?? 0
        let bootstrapHeaderSizes = Self.extractBootstrapHeaders(from: request.bootstrapParts).map(\.count)

        var url = request.streamingURL
        if var components = URLComponents(url: request.streamingURL, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "rn" }
            items.removeAll { $0.name == "cpn" }
            if let queryClientValue = request.transportProfile.queryClientValue {
                items.removeAll { $0.name == "c" }
                items.append(URLQueryItem(name: "c", value: queryClientValue))
            }
            items.append(URLQueryItem(name: "rn", value: request.requestNumber))
            items.append(URLQueryItem(name: "cpn", value: request.contentPlaybackNonce))
            components.queryItems = items
            url = components.url ?? request.streamingURL
        }

        let headers = Self.makeHeaders(client: request.client,
                                       visitorData: request.visitorData,
                                       transportProfile: request.transportProfile)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 30
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        print("[SabrProbe] request start label=\(request.label) client=\(request.client) transportProfile=\(request.transportProfile.rawValue) bodyProfile=\(request.bodyProfile.rawValue) bootstrapStyle=\(request.bootstrapStyle.rawValue) bootstrapHeaderPlacement=\(request.bootstrapHeaderPlacement.rawValue) includeBootstrapHeaders=\(request.includeBootstrapHeaders) url=\(url.absoluteString)")
        print("[SabrProbe] request body bytes=\(requestBody.count) rawBytes=\(payload.count) mode=\(request.mode) currentItag=\(request.currentFormat?.itag ?? -1) videoItag=\(request.videoFormat.itag) audioItag=\(request.audioFormat.itag)")
        print("[SabrProbe] bootstrap token bytes=\(bootstrapTokenLength) bootstrapHeaderSizes=\(bootstrapHeaderSizes) bootstrapParts=\(request.bootstrapParts.map(\.type))")
        print("[SabrProbe] request headers=\(headers)")

        return urlRequest
    }

    func probe(_ request: SabrProbeRequest, completion: @escaping (Result<SabrProbeResult, Error>) -> Void) {
        guard let urlRequest = buildStartupRequest(from: request) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                print("[SabrProbe] request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            let http = response as? HTTPURLResponse
            let body = data ?? Data()
            let prefix = body.prefix(24).map { String(format: "%02x", $0) }.joined()
            let contentType = Self.headerValue(named: "Content-Type", in: http)
            print("[SabrProbe] response status=\(http?.statusCode ?? -1) contentType=\(contentType ?? "nil") bytes=\(body.count)")
            let partTypes = Self.parseUMPPartTypes(from: body)
            if !partTypes.isEmpty {
                print("[SabrProbe] response ump parts=\(partTypes.map(String.init).joined(separator: ","))")
            }
            completion(.success(SabrProbeResult(
                statusCode: http?.statusCode ?? -1,
                contentType: contentType,
                bodySize: body.count,
                bodyPrefixHex: prefix,
                umpPartTypes: partTypes
            )))
        }.resume()
    }

    private static func buildRequestBody(ustreamerConfig: Data,
                                         poToken: Data,
                                         client: DirectPlaybackClient,
                                         transportProfile: SabrProbeRequest.TransportProfile,
                                         audioFormat: SabrFormatInfo,
                                         videoFormat: SabrFormatInfo,
                                         bootstrapParts: [OnesieResponsePart],
                                         currentFormat: SabrFormatInfo?,
                                         mode: SabrProbeRequest.Mode,
                                         bootstrapStyle: SabrProbeRequest.BootstrapStyle,
                                         includeBootstrapHeaders: Bool,
                                         bootstrapHeaderPlacement: SabrProbeRequest.BootstrapHeaderPlacement,
                                         bodyProfile: SabrProbeRequest.BodyProfile,
                                         playbackCookie: Data?,
                                         activeSabrContexts: [SabrContextState],
                                         unsentSabrContextTypes: [Int]) -> Data {
        var body = Data()

        let clientAbrState = encodeClientAbrState(audioFormat: audioFormat,
                                                 videoFormat: videoFormat,
                                                 currentFormat: currentFormat,
                                                 mode: mode,
                                                 profile: bodyProfile)
        let bootstrapToken = extractBootstrapToken(from: bootstrapParts)

        appendLengthDelimited(fieldNumber: 1, payload: clientAbrState, to: &body)
        if mode == .current, let currentFormat {
            appendLengthDelimited(fieldNumber: 2, payload: encodeFormatId(currentFormat), to: &body)
        } else {
            appendLengthDelimited(fieldNumber: 2, payload: encodeFormatId(audioFormat), to: &body)
            appendLengthDelimited(fieldNumber: 2, payload: encodeFormatId(videoFormat), to: &body)
        }
        bufferedRanges(audioFormat: audioFormat,
                       videoFormat: videoFormat,
                       currentFormat: currentFormat,
                       mode: mode).forEach {
            appendLengthDelimited(fieldNumber: 3, payload: $0, to: &body)
        }
        if let playerTimeMs = playerTimeMs(mode: mode, currentFormat: currentFormat), playerTimeMs > 0 {
            appendInt64(fieldNumber: 4, value: UInt64(playerTimeMs), to: &body)
        }
        appendLengthDelimited(fieldNumber: 5, payload: ustreamerConfig, to: &body)
        appendLengthDelimited(fieldNumber: 16, payload: encodeFormatId(audioFormat), to: &body)
        appendLengthDelimited(fieldNumber: 17, payload: encodeFormatId(videoFormat), to: &body)
        appendLengthDelimited(fieldNumber: 19,
                              payload: encodeStreamerContext(poToken: poToken,
                                                             playbackCookie: playbackCookie ?? (bootstrapStyle == .cookieField3 ? bootstrapToken : nil),
                                                             bootstrapToken: bootstrapStyle == .tokenField4 ? bootstrapToken : nil,
                                                             activeSabrContexts: activeSabrContexts,
                                                             unsentSabrContextTypes: unsentSabrContextTypes,
                                                             client: client,
                                                             transportProfile: transportProfile),
                              to: &body)
        return body
    }

    private static func playerTimeMs(mode: SabrProbeRequest.Mode,
                                     currentFormat: SabrFormatInfo?) -> Int? {
        switch mode {
        case .startup:
            return nil
        case .current:
            return currentFormat == nil ? nil : 0
        }
    }

    private static func encodeClientAbrState(audioFormat: SabrFormatInfo,
                                             videoFormat: SabrFormatInfo,
                                             currentFormat: SabrFormatInfo?,
                                             mode: SabrProbeRequest.Mode,
                                             profile: SabrProbeRequest.BodyProfile) -> Data {
        var data = Data()
        let audioBitrate = max(audioFormat.bitrate ?? 0, 0)
        let videoBitrate = max(videoFormat.bitrate ?? 0, 0)
        let combinedBitrate = audioBitrate + videoBitrate
        let selectedFormat = currentFormat ?? videoFormat
        appendInt64(fieldNumber: 28, value: 0, to: &data) // playerTimeMs
        if let audioTrackId = audioFormat.audioTrackId, !audioTrackId.isEmpty {
            appendString(fieldNumber: 69, value: audioTrackId, to: &data)
        }
        if let height = videoFormat.height, height > 0 {
            appendInt32(fieldNumber: 21, value: height, to: &data) // stickyResolution
            if mode == .current {
                appendInt32(fieldNumber: 16, value: height, to: &data) // lastManualSelectedResolution
            }
        }
        appendBool(fieldNumber: 22, value: false, to: &data) // clientViewportIsFlexible
        appendInt32(fieldNumber: 34, value: 1, to: &data) // visibility
        appendFloat(fieldNumber: 35, value: 1.0, to: &data) // playbackRate
        if mode == .startup {
            appendInt32(fieldNumber: 40, value: 0, to: &data) // video and audio
        } else {
            appendInt64(fieldNumber: 23, value: 0, to: &data) // bandwidthEstimate
            appendInt32(fieldNumber: 40, value: currentFormat?.width != nil ? 2 : 1, to: &data)
        }
        if audioFormat.isDrc {
            appendBool(fieldNumber: 46, value: true, to: &data)
        }
        guard profile != .lean else {
            return data
        }

        if let width = selectedFormat.width, width > 0 {
            appendInt32(fieldNumber: 17, value: width, to: &data)
        }
        if let height = selectedFormat.height, height > 0 {
            appendInt32(fieldNumber: 18, value: height, to: &data)
            appendInt32(fieldNumber: 36, value: height, to: &data)
        }
        if videoBitrate > 0 {
            appendInt64(fieldNumber: 19, value: UInt64(videoBitrate), to: &data)
            appendInt64(fieldNumber: 39, value: UInt64(videoBitrate), to: &data)
        }
        if combinedBitrate > 0 {
            appendInt64(fieldNumber: 23, value: UInt64(combinedBitrate), to: &data)
            appendInt64(fieldNumber: 42, value: UInt64(combinedBitrate), to: &data)
        }
        if audioBitrate > 0 {
            appendInt64(fieldNumber: 27, value: UInt64(audioBitrate), to: &data)
        }
        appendInt32(fieldNumber: 29, value: 1, to: &data)
        appendBool(fieldNumber: 32, value: true, to: &data)
        appendInt32(fieldNumber: 41, value: 0, to: &data)
        appendInt32(fieldNumber: 44, value: currentFormat == nil ? 0 : 1, to: &data)
        if profile == .richStartup {
            appendInt32(fieldNumber: 38, value: 1, to: &data)
            appendInt32(fieldNumber: 45, value: 1, to: &data)
        }
        return data
    }

    private static func bufferedRanges(audioFormat: SabrFormatInfo,
                                       videoFormat: SabrFormatInfo,
                                       currentFormat: SabrFormatInfo?,
                                       mode: SabrProbeRequest.Mode) -> [Data] {
        let maxRangeValue = Int(Int32.max)

        switch mode {
        case .startup:
            return [
                encodeBufferedRange(format: videoFormat,
                                    startTimeMs: 0,
                                    durationMs: maxRangeValue,
                                    startSegmentIndex: maxRangeValue,
                                    endSegmentIndex: maxRangeValue),
                encodeBufferedRange(format: audioFormat,
                                    startTimeMs: 0,
                                    durationMs: maxRangeValue,
                                    startSegmentIndex: maxRangeValue,
                                    endSegmentIndex: maxRangeValue)
            ]
        case .current:
            guard let currentFormat else {
                return []
            }
            let otherFormat = currentFormat.width != nil ? audioFormat : videoFormat
            return [
                encodeBufferedRange(format: otherFormat,
                                    startTimeMs: 0,
                                    durationMs: maxRangeValue,
                                    startSegmentIndex: maxRangeValue,
                                    endSegmentIndex: maxRangeValue),
                encodeBufferedRange(format: currentFormat,
                                    startTimeMs: 0,
                                    durationMs: 0,
                                    startSegmentIndex: 1,
                                    endSegmentIndex: 1)
            ]
        }
    }

    private static func encodeBufferedRange(format: SabrFormatInfo,
                                            startTimeMs: Int,
                                            durationMs: Int,
                                            startSegmentIndex: Int,
                                            endSegmentIndex: Int) -> Data {
        var data = Data()
        appendLengthDelimited(fieldNumber: 1, payload: encodeFormatId(format), to: &data)
        appendInt64(fieldNumber: 2, value: UInt64(max(startTimeMs, 0)), to: &data)
        appendInt64(fieldNumber: 3, value: UInt64(max(durationMs, 0)), to: &data)
        appendInt32(fieldNumber: 4, value: startSegmentIndex, to: &data)
        appendInt32(fieldNumber: 5, value: endSegmentIndex, to: &data)
        appendLengthDelimited(fieldNumber: 6,
                              payload: encodeTimeRange(startTicks: startTimeMs,
                                                       durationTicks: durationMs,
                                                       timescale: 1000),
                              to: &data)
        return data
    }

    private static func encodeTimeRange(startTicks: Int,
                                        durationTicks: Int,
                                        timescale: Int) -> Data {
        var data = Data()
        appendInt64(fieldNumber: 1, value: UInt64(max(startTicks, 0)), to: &data)
        appendInt64(fieldNumber: 2, value: UInt64(max(durationTicks, 0)), to: &data)
        appendInt32(fieldNumber: 3, value: timescale, to: &data)
        return data
    }

    private static func encodeStreamerContext(poToken: Data,
                                              playbackCookie: Data?,
                                              bootstrapToken: Data?,
                                              activeSabrContexts: [SabrContextState],
                                              unsentSabrContextTypes: [Int],
                                              client: DirectPlaybackClient,
                                              transportProfile: SabrProbeRequest.TransportProfile) -> Data {
        var data = Data()
        appendLengthDelimited(fieldNumber: 1, payload: encodeClientInfo(client: client, transportProfile: transportProfile), to: &data)
        appendLengthDelimited(fieldNumber: 2, payload: poToken, to: &data)
        if let playbackCookie, !playbackCookie.isEmpty {
            appendLengthDelimited(fieldNumber: 3, payload: playbackCookie, to: &data)
        }
        if let bootstrapToken, !bootstrapToken.isEmpty {
            appendLengthDelimited(fieldNumber: 4, payload: bootstrapToken, to: &data)
        }
        for context in activeSabrContexts {
            var contextPayload = Data()
            appendInt32(fieldNumber: 1, value: context.type, to: &contextPayload)
            appendLengthDelimited(fieldNumber: 2, payload: context.value, to: &contextPayload)
            appendLengthDelimited(fieldNumber: 5, payload: contextPayload, to: &data)
        }
        if !unsentSabrContextTypes.isEmpty {
            appendTag(fieldNumber: 6, wireType: 2, to: &data)
            var packed = Data()
            unsentSabrContextTypes.forEach { appendVarint(UInt64($0), to: &packed) }
            appendVarint(UInt64(packed.count), to: &data)
            data.append(packed)
        }
        return data
    }

    private static func encodeClientInfo(client: DirectPlaybackClient,
                                         transportProfile: SabrProbeRequest.TransportProfile) -> Data {
        var data = Data()
        let clientName: Int
        let clientVersion: String
        let deviceMake: String
        let deviceModel: String
        let osName: String
        let osVersion: String
        let acceptLanguage: String
        let acceptRegion: String
        let screenWidth: Int
        let screenHeight: Int
        let pixelDensity: Int
        let screenDensityFloat: Float
        let clientFormFactor: Int
        switch transportProfile {
        case .tvHTML5, .tvHTML5Brotli:
            switch client {
            case .tvHTML5:
                clientName = 7
                clientVersion = "7.20230405.08.01"
            case .web:
                clientName = 1
                clientVersion = "2.20231121.08.00"
            case .android:
                clientName = 3
                clientVersion = DirectPlaybackClient.android.clientVersion
            }
            deviceMake = "Google"
            deviceModel = "Chromecast"
            osName = "Cobalt"
            osVersion = "Unknown"
            acceptLanguage = "en-US"
            acceptRegion = "US"
            screenWidth = 1920
            screenHeight = 1080
            pixelDensity = 1
            screenDensityFloat = 1.0
            clientFormFactor = 2
        case .iosApp, .iosAppBrotli:
            clientName = 5
            clientVersion = "20.21.6"
            deviceMake = "Apple"
            deviceModel = "iPad4,4"
            osName = "iOS"
            osVersion = "15.8.5"
            acceptLanguage = "ru-PT"
            acceptRegion = "PT"
            screenWidth = 768
            screenHeight = 1024
            pixelDensity = 2
            screenDensityFloat = 2.0
            clientFormFactor = 1
        case .tvHTML5Bare, .tvHTML5BareBrotli:
            clientName = 7
            clientVersion = DirectPlaybackClient.tvHTML5.clientVersion
            deviceMake = "Google"
            deviceModel = "Chromecast"
            osName = "Cobalt"
            osVersion = "Unknown"
            acceptLanguage = "en-US"
            acceptRegion = "US"
            screenWidth = 1920
            screenHeight = 1080
            pixelDensity = 1
            screenDensityFloat = 1.0
            clientFormFactor = 2
        }

        appendString(fieldNumber: 12, value: deviceMake, to: &data)
        appendString(fieldNumber: 13, value: deviceModel, to: &data)
        appendInt32(fieldNumber: 16, value: clientName, to: &data)
        appendString(fieldNumber: 17, value: clientVersion, to: &data)
        appendString(fieldNumber: 18, value: osName, to: &data)
        appendString(fieldNumber: 19, value: osVersion, to: &data)
        appendString(fieldNumber: 21, value: acceptLanguage, to: &data)
        appendString(fieldNumber: 22, value: acceptRegion, to: &data)
        appendInt32(fieldNumber: 37, value: screenWidth, to: &data)
        appendInt32(fieldNumber: 38, value: screenHeight, to: &data)
        appendFloat(fieldNumber: 39, value: Float(screenWidth) / 160.0, to: &data)
        appendFloat(fieldNumber: 40, value: Float(screenHeight) / 160.0, to: &data)
        appendInt32(fieldNumber: 41, value: pixelDensity, to: &data)
        appendInt32(fieldNumber: 46, value: clientFormFactor, to: &data)
        appendInt32(fieldNumber: 55, value: screenWidth, to: &data)
        appendInt32(fieldNumber: 56, value: screenHeight, to: &data)
        appendFloat(fieldNumber: 65, value: screenDensityFloat, to: &data)
        appendInt64(fieldNumber: 67,
                    value: UInt64(bitPattern: Int64(TimeZone.current.secondsFromGMT() / 60)),
                    to: &data)
        appendString(fieldNumber: 80, value: TimeZone.current.identifier, to: &data)
        return data
    }

    private static func encodeFormatId(_ format: SabrFormatInfo) -> Data {
        var data = Data()
        appendInt32(fieldNumber: 1, value: format.itag, to: &data)
        if let lastModified = format.lastModified, !lastModified.isEmpty {
            appendInt64String(fieldNumber: 2, value: lastModified, to: &data)
        }
        if let xtags = format.xtags, !xtags.isEmpty {
            appendString(fieldNumber: 3, value: xtags, to: &data)
        }
        return data
    }

    private static func appendLengthDelimited(fieldNumber: Int, payload: Data, to data: inout Data) {
        appendTag(fieldNumber: fieldNumber, wireType: 2, to: &data)
        appendVarint(UInt64(payload.count), to: &data)
        data.append(payload)
    }

    private static func appendString(fieldNumber: Int, value: String, to data: inout Data) {
        guard let encoded = value.data(using: .utf8) else { return }
        appendLengthDelimited(fieldNumber: fieldNumber, payload: encoded, to: &data)
    }

    private static func appendInt32(fieldNumber: Int, value: Int, to data: inout Data) {
        appendTag(fieldNumber: fieldNumber, wireType: 0, to: &data)
        appendVarint(UInt64(bitPattern: Int64(value)), to: &data)
    }

    private static func appendInt64String(fieldNumber: Int, value: String, to data: inout Data) {
        guard let intValue = UInt64(value) else { return }
        appendTag(fieldNumber: fieldNumber, wireType: 0, to: &data)
        appendVarint(intValue, to: &data)
    }

    private static func appendSignedInt64String(fieldNumber: Int, value: String, to data: inout Data) {
        guard let intValue = Int64(value) else { return }
        appendTag(fieldNumber: fieldNumber, wireType: 0, to: &data)
        appendVarint(UInt64(bitPattern: intValue), to: &data)
    }

    private static func appendInt64(fieldNumber: Int, value: UInt64, to data: inout Data) {
        appendTag(fieldNumber: fieldNumber, wireType: 0, to: &data)
        appendVarint(value, to: &data)
    }

    private static func appendFloat(fieldNumber: Int, value: Float, to data: inout Data) {
        appendTag(fieldNumber: fieldNumber, wireType: 5, to: &data)
        data.append(contentsOf: withUnsafeBytes(of: value.bitPattern.littleEndian, Array.init))
    }

    private static func appendBool(fieldNumber: Int, value: Bool, to data: inout Data) {
        appendTag(fieldNumber: fieldNumber, wireType: 0, to: &data)
        data.append(value ? 1 : 0)
    }

    private static func appendTag(fieldNumber: Int, wireType: Int, to data: inout Data) {
        appendVarint(UInt64((fieldNumber << 3) | wireType), to: &data)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7f | 0x80))
            value >>= 7
        }
        data.append(UInt8(value))
    }

    static func decodeWebSafeBase64(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: normalized)
    }

    private static func headerValue(named name: String, in response: HTTPURLResponse?) -> String? {
        guard let response else { return nil }
        for (key, value) in response.allHeaderFields {
            guard let headerName = key as? String,
                  headerName.caseInsensitiveCompare(name) == .orderedSame
            else { continue }
            return value as? String
        }
        return nil
    }

    private static func makeHeaders(client: DirectPlaybackClient,
                                    visitorData: String?,
                                    transportProfile: SabrProbeRequest.TransportProfile) -> [String: String] {
        var headers: [String: String]
        switch transportProfile {
        case .tvHTML5, .tvHTML5Brotli:
            headers = [
                "Accept": "application/vnd.yt-ump",
                "Accept-Encoding": "gzip, deflate, br",
                "Accept-Language": "*",
                "Content-Type": "application/x-protobuf",
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/tv",
                "User-Agent": "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
                "X-Origin": "https://www.youtube.com",
                "X-Youtube-Client-Name": client.clientHeaderName,
                "X-Youtube-Client-Version": client.clientVersion
            ]
            if transportProfile.usesBrotliBody {
                headers["Content-Encoding"] = "br"
            }
        case .tvHTML5Bare, .tvHTML5BareBrotli:
            headers = [
                "User-Agent": "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
                "Accept-Encoding": "gzip, deflate, br"
            ]
            if transportProfile.usesBrotliBody {
                headers["Content-Encoding"] = "br"
            }
        case .iosApp, .iosAppBrotli:
            headers = [
                "Accept": "application/vnd.yt-ump",
                "Content-Type": "application/x-protobuf",
                "User-Agent": "com.google.ios.youtube/20.21.6 (iPad4,4; U; CPU iOS 15_8_5 like Mac OS X; ru_PT)",
                "Accept-Encoding": "gzip, deflate, br"
            ]
            if transportProfile.usesBrotliBody {
                headers["Content-Encoding"] = "br"
            }
        }
        if let visitorData, !visitorData.isEmpty, transportProfile == .tvHTML5 || transportProfile == .tvHTML5Brotli {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        return headers
    }

    private static func brotliCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return data }

        let destinationBufferSize = 64 * 1024
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }
        let initialDestinationPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let initialSourcePointer = UnsafePointer<UInt8>(initialDestinationPointer)
        defer { initialDestinationPointer.deallocate() }

        var stream = compression_stream(dst_ptr: initialDestinationPointer,
                                        dst_size: 0,
                                        src_ptr: initialSourcePointer,
                                        src_size: 0,
                                        state: nil)
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_BROTLI)
        guard status != COMPRESSION_STATUS_ERROR else { return nil }
        defer { compression_stream_destroy(&stream) }

        let output: Data? = data.withUnsafeBytes { sourceBuffer -> Data? in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            var output = Data()
            stream.src_ptr = sourcePointer
            stream.src_size = data.count

            repeat {
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR else { return nil }
                output.append(destinationBuffer, count: destinationBufferSize - stream.dst_size)
            } while status == COMPRESSION_STATUS_OK

            return status == COMPRESSION_STATUS_END ? output : nil
        }
        return output
    }

    private static func parseUMPPartTypes(from data: Data) -> [Int] {
        let reader = SabrUMPReader()
        reader.append(data)
        return reader.readAvailableParts(limit: 8).map(\.type)
    }

    private static func extractBootstrapToken(from bootstrapParts: [OnesieResponsePart]) -> Data? {
        bootstrapParts.first(where: { $0.type == 2 })?.payload
    }

    private static func extractBootstrapHeaders(from bootstrapParts: [OnesieResponsePart]) -> [Data] {
        bootstrapParts
            .filter { $0.type == 11 && !$0.payload.isEmpty }
            .map(\.payload)
    }
}
