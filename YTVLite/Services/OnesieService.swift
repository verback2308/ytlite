import Foundation
import CommonCrypto
import zlib

// MARK: - Errors

enum OnesieError: Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case parseError(String)
    case encryptError
    case invalidRedirector
    case encodeError

    var description: String {
        switch self {
        case .invalidURL: return "invalid URL"
        case .invalidResponse: return "invalid response"
        case .parseError(let msg): return "parse error: \(msg)"
        case .encryptError: return "encryption error"
        case .invalidRedirector: return "invalid redirector response"
        case .encodeError: return "encode error"
        }
    }
}

// MARK: - Hot Config

struct OnesieHotConfig {
    let clientKeyData: Data
    let encryptedClientKey: Data
    let onesieUstreamerConfig: Data
    let baseUrl: String
    let keyExpiresInSeconds: Int
    let fetchedAt: Date

    var isValid: Bool {
        Date().timeIntervalSince(fetchedAt) < Double(keyExpiresInSeconds)
    }
}

struct OnesieResponsePart {
    let type: Int
    let compressionType: Int
    let payload: Data
}

struct OnesiePlaybackBootstrap {
    let playerJSON: [String: Any]
    let responseParts: [OnesieResponsePart]
    let proxyStatus: Int
    let httpStatus: Int
}

struct OnesieAbrRoute {
    let url: URL
    let ustreamerConfig: Data
}

// MARK: - Service

final class OnesieService {
    static let shared = OnesieService()

    private var cachedConfig: OnesieHotConfig?
    private var cachedRedirectorHost: String?
    private let queue = DispatchQueue(label: "com.ytvlite.onesie")

    private init() {}

    // MARK: - Public

    /// Fetches the YouTube player response via the onesie/initplayback path.
    /// Returns the raw player JSON dict on success.
    func fetchPlayerResponse(
        videoId: String,
        visitorData: String,
        poToken: String? = nil,
        contentPlaybackNonce: String? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        fetchPlaybackBootstrap(videoId: videoId,
                               visitorData: visitorData,
                               poToken: poToken,
                               contentPlaybackNonce: contentPlaybackNonce) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let bootstrap):
                completion(.success(bootstrap.playerJSON))
            }
        }
    }

    func fetchPlaybackBootstrap(
        videoId: String,
        visitorData: String,
        poToken: String? = nil,
        contentPlaybackNonce: String? = nil,
        completion: @escaping (Result<OnesiePlaybackBootstrap, Error>) -> Void
    ) {
        // Get OAuth token so the tunnelled Innertube request is authenticated
        OAuthClient.shared.validToken { [weak self] tokenResult in
            let authToken: String?
            if case .success(let t) = tokenResult { authToken = t } else { authToken = nil }

            self?.fetchHotConfig { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let config):
                    self?.fetchRedirectorHost { result in
                        switch result {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success(let redirectorHost):
                            self?.executeOnesie(
                                videoId: videoId,
                                visitorData: visitorData,
                                poToken: poToken,
                                authToken: authToken,
                                config: config,
                                redirectorHost: redirectorHost,
                                contentPlaybackNonce: contentPlaybackNonce,
                                completion: completion
                            )
                        }
                    }
                }
            }
        }
    }

    func fetchAbrRoute(videoId: String,
                       audioItag: Int,
                       videoItag: Int,
                       completion: @escaping (Result<OnesieAbrRoute, Error>) -> Void) {
        fetchHotConfig { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let config):
                self?.fetchRedirectorHost { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let redirectorHost):
                        let videoIdHex = Self.encodeVideoId(videoId)
                        let routeString = "\(redirectorHost)\(config.baseUrl)&id=\(videoIdHex)&cmo:sensitive_content=yes&opr=1&osts=0&por=1&owc=yes&alr=yes&rn=0&pvi=\(videoItag)&pai=\(audioItag)"
                        guard let url = URL(string: routeString) else {
                            completion(.failure(OnesieError.invalidURL))
                            return
                        }
                        completion(.success(OnesieAbrRoute(url: url, ustreamerConfig: config.onesieUstreamerConfig)))
                    }
                }
            }
        }
    }

    // MARK: - tv_config fetch

    private func fetchHotConfig(completion: @escaping (Result<OnesieHotConfig, Error>) -> Void) {
        queue.async { [weak self] in
            if let cached = self?.cachedConfig, cached.isValid {
                completion(.success(cached))
                return
            }

            guard let url = URL(string: "https://www.youtube.com/tv_config?action_get_config=true&client=lb4&theme=cl") else {
                completion(.failure(OnesieError.invalidURL)); return
            }

            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15

            URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
                if let error = error { completion(.failure(error)); return }

                // Response starts with ")]}'" — skip first 4 bytes
                guard let data = data, data.count > 4 else {
                    completion(.failure(OnesieError.invalidResponse)); return
                }

                let jsonData = data.dropFirst(4)
                guard
                    let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                    let wpcc = json["webPlayerContextConfig"] as? [String: Any],
                    let lrWatch = wpcc["WEB_PLAYER_CONTEXT_CONFIG_ID_LIVING_ROOM_WATCH"] as? [String: Any],
                    let hc = lrWatch["onesieHotConfig"] as? [String: Any],
                    let clientKeyB64 = hc["clientKey"] as? String,
                    let encKeyB64 = hc["encryptedClientKey"] as? String,
                    let ustreamerB64 = hc["onesieUstreamerConfig"] as? String,
                    let baseUrl = hc["baseUrl"] as? String,
                    let clientKeyData = Self.decodeWebSafeBase64(clientKeyB64),
                    let encryptedClientKey = Self.decodeWebSafeBase64(encKeyB64),
                    let onesieUstreamerConfig = Self.decodeWebSafeBase64(ustreamerB64)
                else {
                    print("[OnesieService] tv_config parse failed")
                    completion(.failure(OnesieError.parseError("tv_config structure"))); return
                }

                let keyExpires = hc["keyExpiresInSeconds"] as? Int ?? 3600
                let config = OnesieHotConfig(
                    clientKeyData: clientKeyData,
                    encryptedClientKey: encryptedClientKey,
                    onesieUstreamerConfig: onesieUstreamerConfig,
                    baseUrl: baseUrl,
                    keyExpiresInSeconds: keyExpires,
                    fetchedAt: Date()
                )
                print("[OnesieService] hot config OK: baseUrl=\(baseUrl) keyExpires=\(keyExpires)s")
                self?.queue.async { self?.cachedConfig = config }
                completion(.success(config))
            }.resume()
        }
    }

    // MARK: - Redirector fetch

    private func fetchRedirectorHost(completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            if let cached = self?.cachedRedirectorHost {
                completion(.success(cached))
                return
            }

            let randId = Int.random(in: 0..<100000)
            let urlStr = "https://redirector.googlevideo.com/initplayback?source=youtube&itag=0&pvi=0&pai=0&owc=yes&cmo:sensitive_content=yes&alr=yes&id=\(randId)"
            guard let url = URL(string: urlStr) else {
                completion(.failure(OnesieError.invalidURL)); return
            }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                if let error = error { completion(.failure(error)); return }

                guard
                    let data = data,
                    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    text.hasPrefix("https://")
                else {
                    completion(.failure(OnesieError.invalidRedirector)); return
                }

                // Strip /initplayback path to get just the host portion
                let host = text.components(separatedBy: "/initplayback").first ?? text
                print("[OnesieService] redirector host: \(host)")
                self?.queue.async { self?.cachedRedirectorHost = host }
                completion(.success(host))
            }.resume()
        }
    }

    // MARK: - Onesie request

    private func executeOnesie(
        videoId: String,
        visitorData: String,
        poToken: String?,
        authToken: String?,
        config: OnesieHotConfig,
        redirectorHost: String,
        contentPlaybackNonce: String?,
        completion: @escaping (Result<OnesiePlaybackBootstrap, Error>) -> Void
    ) {
        // Innertube player request body (TVHTML5 context)
        let innertubeBody: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "TVHTML5",
                    "clientVersion": DirectPlaybackClient.tvHTML5.clientVersion,
                    "hl": "en",
                    "gl": "US",
                    "visitorData": visitorData
                ]
            ],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "serviceIntegrityDimensions": (poToken.map { ["poToken": $0] } ?? [:])
        ]

        guard
            let bodyJSON = try? JSONSerialization.data(withJSONObject: innertubeBody),
            let bodyString = String(data: bodyJSON, encoding: .utf8)
        else {
            completion(.failure(OnesieError.encodeError)); return
        }

        let playerURL = "https://youtubei.googleapis.com/youtubei/v1/player?key=AIzaSyDCU8hByM-4DrUqRUYnGn-3llEO78bcxq8"

        // Build OnesieInnertubeRequest protobuf (what gets AES-CTR encrypted)
        // message OnesieInnertubeRequest {
        //   url = 1, headers = 2 (repeated), body = 3, proxied_by_trusted_bandaid = 4, skip_response_encryption = 6
        // }
        var onesieInnerReq = Data()
        Self.appendString(1, value: playerURL, to: &onesieInnerReq)

        // Header: Content-Type
        var h1 = Data()
        Self.appendString(1, value: "Content-Type", to: &h1)
        Self.appendString(2, value: "application/json", to: &h1)
        Self.appendBytes(2, payload: h1, to: &onesieInnerReq)

        // Header: X-Goog-Visitor-Id
        if !visitorData.isEmpty {
            var h2 = Data()
            Self.appendString(1, value: "X-Goog-Visitor-Id", to: &h2)
            Self.appendString(2, value: visitorData, to: &h2)
            Self.appendBytes(2, payload: h2, to: &onesieInnerReq)
        }

        // Header: Authorization
        if let authToken, !authToken.isEmpty {
            var h3 = Data()
            Self.appendString(1, value: "Authorization", to: &h3)
            Self.appendString(2, value: "Bearer \(authToken)", to: &h3)
            Self.appendBytes(2, payload: h3, to: &onesieInnerReq)
        }

        Self.appendString(3, value: bodyString, to: &onesieInnerReq)  // body
        Self.appendBool(4, value: true, to: &onesieInnerReq)          // proxied_by_trusted_bandaid
        Self.appendBool(6, value: true, to: &onesieInnerReq)          // skip_response_encryption

        // Encrypt OnesieInnertubeRequest
        guard let enc = Self.encryptAesCtrHmac(data: onesieInnerReq, clientKeyData: config.clientKeyData) else {
            completion(.failure(OnesieError.encryptError)); return
        }

        // Build InnertubeRequest (field 3 inside OnesieRequest)
        // message InnertubeRequest {
        //   encrypted_onesie_innertube_request = 2, encrypted_client_key = 5,
        //   iv = 6, hmac = 7, serialize_response_as_json = 10,
        //   enable_compression = 14, ustreamer_flags = 15
        // }
        var innertubeReqMsg = Data()
        Self.appendBytes(2, payload: enc.ciphertext, to: &innertubeReqMsg)
        Self.appendBytes(5, payload: config.encryptedClientKey, to: &innertubeReqMsg)
        Self.appendBytes(6, payload: enc.iv, to: &innertubeReqMsg)
        Self.appendBytes(7, payload: enc.hmac, to: &innertubeReqMsg)
        Self.appendBool(10, value: true, to: &innertubeReqMsg)   // serialize_response_as_json
        Self.appendBool(14, value: false, to: &innertubeReqMsg)  // enable_compression = false → avoid gzip
        // ustreamer_flags { send_video_playback_config (field 2) = false }
        var ustreamerFlags = Data()
        Self.appendBool(2, value: false, to: &ustreamerFlags)
        Self.appendBytes(15, payload: ustreamerFlags, to: &innertubeReqMsg)

        // Build StreamerContext (field 10 inside OnesieRequest)
        // StreamerContext { client_info = 1 }
        // ClientInfo { client_name = 16 (int32), client_version = 17 (string) }
        var clientInfo = Data()
        Self.appendInt32(16, value: 7, to: &clientInfo)  // TVHTML5
        Self.appendString(17, value: DirectPlaybackClient.tvHTML5.clientVersion, to: &clientInfo)
        var streamerCtx = Data()
        Self.appendBytes(1, payload: clientInfo, to: &streamerCtx)

        // Build OnesieRequest
        // message OnesieRequest {
        //   innertube_request = 3, onesie_ustreamer_config = 4, streamer_context = 10
        // }
        var onesieReq = Data()
        Self.appendBytes(3, payload: innertubeReqMsg, to: &onesieReq)
        Self.appendBytes(4, payload: config.onesieUstreamerConfig, to: &onesieReq)
        Self.appendBytes(10, payload: streamerCtx, to: &onesieReq)

        // Encode videoId: YouTube video IDs are base64url-encoded; decode to bytes then hex
        let videoIdHex = Self.encodeVideoId(videoId)

        var reqURLStr = "\(redirectorHost)\(config.baseUrl)&id=\(videoIdHex)&cmo:sensitive_content=yes&opr=1&osts=0&por=1&rn=1"
        if let contentPlaybackNonce, !contentPlaybackNonce.isEmpty {
            reqURLStr += "&cpn=\(contentPlaybackNonce)"
        }
        guard let reqURL = URL(string: reqURLStr) else {
            completion(.failure(OnesieError.invalidURL)); return
        }

        print("[OnesieService] POST \(reqURL.absoluteString.prefix(120))...")

        var urlReq = URLRequest(url: reqURL)
        urlReq.httpMethod = "POST"
        urlReq.httpBody = onesieReq
        urlReq.timeoutInterval = 30
        urlReq.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("application/vnd.yt-ump", forHTTPHeaderField: "Accept")
        urlReq.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        urlReq.setValue("Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version", forHTTPHeaderField: "User-Agent")
        urlReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        urlReq.setValue("https://www.youtube.com/tv", forHTTPHeaderField: "Referer")
        urlReq.setValue("https://www.youtube.com", forHTTPHeaderField: "X-Origin")
        urlReq.setValue(DirectPlaybackClient.tvHTML5.clientHeaderName, forHTTPHeaderField: "X-Youtube-Client-Name")
        urlReq.setValue(DirectPlaybackClient.tvHTML5.clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        urlReq.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")

        URLSession.shared.dataTask(with: urlReq) { data, response, error in
            if let error = error {
                print("[OnesieService] request failed: \(error.localizedDescription)")
                completion(.failure(error)); return
            }

            let http = response as? HTTPURLResponse
            let body = data ?? Data()
            print("[OnesieService] response status=\(http?.statusCode ?? -1) bytes=\(body.count)")

            guard let bootstrap = Self.parseUMPResponse(body) else {
                completion(.failure(OnesieError.parseError("UMP response"))); return
            }

            completion(.success(bootstrap))
        }.resume()
    }

    // MARK: - UMP Response Parsing

    private static func parseUMPResponse(_ data: Data) -> OnesiePlaybackBootstrap? {
        let reader = SabrUMPReader()
        reader.append(data)
        let parts = reader.readAvailableParts(limit: 64)

        var pendingHeaders: [OnesieHeaderInfo] = []
        var playerResponseEntry: (compressionType: Int, data: Data)?
        var responseParts: [OnesieResponsePart] = []

        for part in parts {
            switch part.type {
            case 10: // ONESIE_HEADER
                if let header = parseOnesieHeader(part.payload) {
                    pendingHeaders.append(header)
                    let h = header
                    print("[OnesieService] ONESIE_HEADER type=\(h.type) compression=\(h.compressionType)")
                }
            case 11: // ONESIE_DATA
                if !pendingHeaders.isEmpty {
                    let header = pendingHeaders.removeLast()
                    responseParts.append(OnesieResponsePart(type: header.type,
                                                           compressionType: header.compressionType,
                                                           payload: part.payload))
                    if header.type == 0 { // ONESIE_PLAYER_RESPONSE
                        playerResponseEntry = (header.compressionType, part.payload)
                    }
                }
            case 44: // SABR_ERROR
                print("[OnesieService] SABR_ERROR part in response")
            default:
                print("[OnesieService] UMP part type=\(part.type) size=\(part.size)")
            }
        }

        if !pendingHeaders.isEmpty {
            let droppedTypes = pendingHeaders.map(\.type)
            print("[OnesieService] unpaired ONESIE_HEADER types: \(droppedTypes)")
        }

        guard let (compressionType, responseData) = playerResponseEntry else {
            print("[OnesieService] no ONESIE_PLAYER_RESPONSE (type=0) found in UMP")
            return nil
        }

        // responseData is OnesieInnertubeResponse protobuf (NOT compressed).
        // compressionType applies only to field 4 (body) inside it.
        guard
            let proxyStatus = extractVarintField(fieldNumber: 1, from: responseData),
            let httpStatus = extractVarintField(fieldNumber: 2, from: responseData),
            let rawBody = extractBytesField(fieldNumber: 4, from: responseData)
        else {
            print("[OnesieService] OnesieInnertubeResponse parse failed")
            return nil
        }

        print("[OnesieService] proxy_status=\(proxyStatus) http_status=\(httpStatus) body=\(rawBody.count)B compression=\(compressionType)")

        guard proxyStatus == 1 /* OK */, httpStatus == 200 else {
            print("[OnesieService] non-OK status: proxy=\(proxyStatus) http=\(httpStatus)")
            return nil
        }

        print("[OnesieService] rawBody first bytes: \(rawBody.prefix(8).map { String(format: "%02x", $0) }.joined())")

        // Try JSON parse first (server may send uncompressed despite compression_type=1)
        let bodyBytes: Data
        if let _ = try? JSONSerialization.jsonObject(with: rawBody) {
            bodyBytes = rawBody
        } else if compressionType == 1, let decompressed = gunzip(rawBody) {
            print("[OnesieService] gzip decompressed \(rawBody.count)B → \(decompressed.count)B")
            bodyBytes = decompressed
        } else {
            print("[OnesieService] body is neither JSON nor gzip (\(rawBody.count)B)")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyBytes) as? [String: Any] else {
            print("[OnesieService] player response JSON parse failed, first bytes: \(bodyBytes.prefix(16).map { String(format: "%02x", $0) }.joined())")
            return nil
        }

        let partSummary = responseParts
            .map { "\($0.type):\($0.payload.count)B/c\($0.compressionType)" }
            .joined(separator: ",")
        print("[OnesieService] captured parts: [\(partSummary)]")

        return OnesiePlaybackBootstrap(
            playerJSON: json,
            responseParts: responseParts,
            proxyStatus: proxyStatus,
            httpStatus: httpStatus
        )
    }

    private struct OnesieHeaderInfo {
        let type: Int           // OnesieHeaderType enum: 0 = ONESIE_PLAYER_RESPONSE
        let compressionType: Int // 0=none, 1=gzip, 2=brotli
    }

    private static func parseOnesieHeader(_ data: Data) -> OnesieHeaderInfo? {
        // OnesieHeader { type=1(varint), crypto_params=4(message { compression_type=6(varint) }) }
        let type = extractVarintField(fieldNumber: 1, from: data) ?? 0
        let cryptoData = extractBytesField(fieldNumber: 4, from: data)
        let compression = cryptoData.flatMap { extractVarintField(fieldNumber: 6, from: $0) } ?? 0
        return OnesieHeaderInfo(type: type, compressionType: compression)
    }

    // MARK: - Protobuf encode helpers

    private static func appendTag(_ fieldNumber: Int, wireType: Int, to data: inout Data) {
        appendRawVarint(UInt64((fieldNumber << 3) | wireType), to: &data)
    }

    private static func appendRawVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7f | 0x80))
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private static func appendBytes(_ fieldNumber: Int, payload: Data, to data: inout Data) {
        appendTag(fieldNumber, wireType: 2, to: &data)
        appendRawVarint(UInt64(payload.count), to: &data)
        data.append(payload)
    }

    private static func appendString(_ fieldNumber: Int, value: String, to data: inout Data) {
        guard let encoded = value.data(using: .utf8) else { return }
        appendBytes(fieldNumber, payload: encoded, to: &data)
    }

    private static func appendBool(_ fieldNumber: Int, value: Bool, to data: inout Data) {
        appendTag(fieldNumber, wireType: 0, to: &data)
        data.append(value ? 1 : 0)
    }

    private static func appendInt32(_ fieldNumber: Int, value: Int, to data: inout Data) {
        appendTag(fieldNumber, wireType: 0, to: &data)
        appendRawVarint(UInt64(bitPattern: Int64(value)), to: &data)
    }

    // MARK: - Protobuf decode helpers (standard protobuf varint, not UMP varint)

    private static func extractVarintField(fieldNumber: Int, from data: Data) -> Int? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOff) = readProtoVarint(data, offset: offset) else { return nil }
            let wt = tag & 0x7
            let fn = tag >> 3
            offset = nextOff
            if fn == fieldNumber, wt == 0 {
                return readProtoVarint(data, offset: offset)?.0
            }
            guard let skip = skipProtoField(wireType: wt, in: data, offset: offset) else { return nil }
            offset = skip
        }
        return nil
    }

    private static func extractBytesField(fieldNumber: Int, from data: Data) -> Data? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOff) = readProtoVarint(data, offset: offset) else { return nil }
            let wt = tag & 0x7
            let fn = tag >> 3
            offset = nextOff
            if fn == fieldNumber, wt == 2 {
                guard let (length, valOff) = readProtoVarint(data, offset: offset),
                      valOff + length <= data.count else { return nil }
                return data.subdata(in: valOff..<(valOff + length))
            }
            guard let skip = skipProtoField(wireType: wt, in: data, offset: offset) else { return nil }
            offset = skip
        }
        return nil
    }

    private static func readProtoVarint(_ data: Data, offset: Int) -> (Int, Int)? {
        var result = 0
        var shift = 0
        var off = offset
        while off < data.count {
            let byte = Int(data[off])
            off += 1
            result |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 { return (result, off) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private static func skipProtoField(wireType: Int, in data: Data, offset: Int) -> Int? {
        switch wireType {
        case 0: return readProtoVarint(data, offset: offset)?.1
        case 2:
            guard let (len, off) = readProtoVarint(data, offset: offset), off + len <= data.count else { return nil }
            return off + len
        case 5: return offset + 4 <= data.count ? offset + 4 : nil
        case 1: return offset + 8 <= data.count ? offset + 8 : nil
        default: return nil
        }
    }

    // MARK: - AES-CTR + HMAC-SHA256

    private struct EncryptedData {
        let ciphertext: Data
        let hmac: Data
        let iv: Data
    }

    private static func encryptAesCtrHmac(data: Data, clientKeyData: Data) -> EncryptedData? {
        guard clientKeyData.count == 32 else {
            print("[OnesieService] clientKeyData wrong length: \(clientKeyData.count)")
            return nil
        }

        let aesKey = clientKeyData.prefix(16)
        let hmacKey = clientKeyData.suffix(16)

        var iv = Data(count: 16)
        let secResult = iv.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard secResult == errSecSuccess else { return nil }

        guard let ciphertext = aesCTR(data: data, key: aesKey, iv: iv) else { return nil }

        var toSign = ciphertext
        toSign.append(iv)
        guard let hmac = hmacSHA256(data: toSign, key: hmacKey) else { return nil }

        return EncryptedData(ciphertext: ciphertext, hmac: hmac, iv: iv)
    }

    private static func aesCTR(data: Data, key: Data, iv: Data) -> Data? {
        var cryptorRef: CCCryptorRef?
        // CCCryptorCreateWithMode(op, mode, alg, padding, iv, key, keyLen, tweak, tweakLen, numRounds, options, &ref)
        let createStatus = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(0),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptorRef
                )
            }
        }
        guard createStatus == kCCSuccess, let ref = cryptorRef else {
            print("[OnesieService] CCCryptorCreateWithMode failed: \(createStatus)")
            return nil
        }
        defer { CCCryptorRelease(ref) }

        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var moved = 0
        let updateStatus = data.withUnsafeBytes { dataPtr in
            output.withUnsafeMutableBytes { outPtr in
                CCCryptorUpdate(ref, dataPtr.baseAddress, data.count, outPtr.baseAddress, outputCapacity, &moved)
            }
        }
        guard updateStatus == kCCSuccess else {
            print("[OnesieService] CCCryptorUpdate failed: \(updateStatus)")
            return nil
        }
        return output.prefix(moved)
    }

    private static func hmacSHA256(data: Data, key: Data) -> Data? {
        var result = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        result.withUnsafeMutableBytes { resultPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyPtr.baseAddress, key.count,
                        dataPtr.baseAddress, data.count,
                        resultPtr.baseAddress
                    )
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func gunzip(_ data: Data) -> Data? {
        guard data.count > 2, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        let chunkSize = 4096
        var result = Data()
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var status = Z_OK
        data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: rawPtr.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(rawPtr.count)
            while status == Z_OK {
                let produced = chunk.withUnsafeMutableBufferPointer { bufPtr -> Int in
                    stream.next_out = bufPtr.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }
                if status < 0 { result.removeAll(); return }
                result.append(contentsOf: chunk.prefix(produced))
            }
            if status != Z_STREAM_END { result.removeAll() }
        }
        return result.isEmpty ? nil : result
    }

    private static func encodeVideoId(_ videoId: String) -> String {
        // YouTube video IDs are base64url-encoded — decode to raw bytes, then hex-encode
        var normalized = videoId
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 { normalized.append(String(repeating: "=", count: 4 - remainder)) }
        if let decoded = Data(base64Encoded: normalized) {
            return decoded.map { String(format: "%02x", $0) }.joined()
        }
        // Fallback: hex-encode UTF-8 bytes
        return videoId.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? videoId
    }

    private static func decodeWebSafeBase64(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 { normalized.append(String(repeating: "=", count: 4 - remainder)) }
        return Data(base64Encoded: normalized)
    }
}
