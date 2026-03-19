import Foundation

struct SabrSessionConfiguration {
    let videoId: String
    let streamingURL: URL
    let videoPlaybackUstreamerConfig: Data
    let contentPoToken: String
    let contentPlaybackNonce: String
    let client: DirectPlaybackClient
    let visitorData: String?
    let audioFormat: SabrFormatInfo
    let videoFormat: SabrFormatInfo
    let bootstrapParts: [OnesieResponsePart]
}

struct SabrSessionStartResult {
    let statusCode: Int
    let contentType: String?
    let bodySize: Int
    let umpPartTypes: [Int]
    let rawBody: Data
    let responseHeaders: [String: String]
    let followupStatusCode: Int?
    let followupContentType: String?
    let followupBodySize: Int?
    let followupUMPPartTypes: [Int]
    let followupResponseHeaders: [String: String]
    let followupLabel: String?
}

private struct SabrStartupVariant {
    let label: String
    let startupURL: URL
    let bootstrapStyle: SabrProbeRequest.BootstrapStyle
    let transportProfile: SabrProbeRequest.TransportProfile
    let bodyProfile: SabrProbeRequest.BodyProfile
}

struct SabrSession {
    let id: UUID
    let configuration: SabrSessionConfiguration
    let startedAt: Date
    var requestNumber: Int
    var lastStartResult: SabrSessionStartResult?
    var playbackCookie: Data?
    var sabrContexts: [Int: SabrContextState]
    var activeSabrContextTypes: Set<Int>
    var nextRequestPolicy: SabrNextRequestPolicyState?
}

final class SabrSessionService {
    static let shared = SabrSessionService()

    private let queue = DispatchQueue(label: "com.ytvlite.sabr-session-service")
    private let queueKey = DispatchSpecificKey<Void>()
    private var sessions: [UUID: SabrSession] = [:]
    private var requestCounter = 2

    private init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    func startSession(configuration: SabrSessionConfiguration,
                      completion: @escaping (Result<(SabrSession, SabrSessionStartResult), Error>) -> Void) {
        let sessionId = UUID()
        let session = SabrSession(id: sessionId,
                                  configuration: configuration,
                                  startedAt: Date(),
                                  requestNumber: 0,
                                  lastStartResult: nil,
                                  playbackCookie: nil,
                                  sabrContexts: [:],
                                  activeSabrContextTypes: [],
                                  nextRequestPolicy: nil)

        queue.async {
            self.sessions[sessionId] = session
        }

        let bootstrapTypes = configuration.bootstrapParts.map(\.type)
        print("[SabrSession] start session \(sessionId.uuidString) client=\(configuration.client) bootstrapParts=\(bootstrapTypes) bootstrapContexts=[]")
        let startupVariants = startupVariants(configuration: configuration)
        runStartupVariants(startupVariants,
                           at: 0,
                           sessionId: sessionId,
                           configuration: configuration,
                           completion: completion)
    }

    private func startupVariants(configuration: SabrSessionConfiguration) -> [SabrStartupVariant] {
        return [
            SabrStartupVariant(label: "startup-videoplayback-rich-br",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5Brotli,
                               bodyProfile: .richAbrState),
            SabrStartupVariant(label: "startup-videoplayback-rich",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5,
                               bodyProfile: .richAbrState),
            SabrStartupVariant(label: "startup-videoplayback-bare-rich",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5Bare,
                               bodyProfile: .richAbrState),
            SabrStartupVariant(label: "startup-videoplayback",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5,
                               bodyProfile: .lean),
            SabrStartupVariant(label: "startup-videoplayback-cookie3",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .cookieField3,
                               transportProfile: .tvHTML5,
                               bodyProfile: .richStartup),
            SabrStartupVariant(label: "startup-videoplayback-bare",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5Bare,
                               bodyProfile: .lean),
            SabrStartupVariant(label: "startup-videoplayback-bare-br",
                               startupURL: configuration.streamingURL,
                               bootstrapStyle: .tokenField4,
                               transportProfile: .tvHTML5BareBrotli,
                               bodyProfile: .richAbrState)
        ]
    }

    private func runStartupVariants(_ variants: [SabrStartupVariant],
                                    at index: Int,
                                    sessionId: UUID,
                                    configuration: SabrSessionConfiguration,
                                    completion: @escaping (Result<(SabrSession, SabrSessionStartResult), Error>) -> Void) {
        guard index < variants.count else {
            queue.async {
                guard let stored = self.sessions[sessionId], let last = stored.lastStartResult else {
                    completion(.failure(APIError.decodingFailed))
                    return
                }
                if last.statusCode >= 400 {
                    completion(.failure(APIError.decodingFailed))
                    return
                }
                completion(.success((stored, last)))
            }
            return
        }

        let variant = variants[index]
        let requestNumber = nextRequestNumber()
        let startupRequest = SabrProbeRequest(
            streamingURL: variant.startupURL,
            ustreamerConfigData: configuration.videoPlaybackUstreamerConfig,
            contentPoToken: configuration.contentPoToken,
            client: configuration.client,
            visitorData: configuration.visitorData,
            audioFormat: configuration.audioFormat,
            videoFormat: configuration.videoFormat,
            bootstrapParts: configuration.bootstrapParts,
            currentFormat: nil,
            mode: .startup,
            label: variant.label,
            requestNumber: requestNumber,
            contentPlaybackNonce: configuration.contentPlaybackNonce,
            bootstrapStyle: variant.bootstrapStyle,
            includeBootstrapHeaders: false,
            transportProfile: variant.transportProfile,
            bootstrapHeaderPlacement: .field11,
            bodyProfile: variant.bodyProfile,
            playbackCookie: nil,
            activeSabrContexts: [],
            unsentSabrContextTypes: []
        )

        guard let urlRequest = SabrProbeService.shared.buildStartupRequest(from: startupRequest) else {
            queue.async { self.sessions[sessionId] = nil }
            completion(.failure(APIError.decodingFailed))
            return
        }

        SabrRequestMetadataStore.shared.setMetadata(
            SabrRequestMetadata(
                format: nil,
                isSABR: true,
                isUMP: true,
                isInitSegment: false,
                byteRange: nil,
                timestamp: Date()
            ),
            for: requestNumber
        )

        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                print("[SabrSession] \(variant.label) failed \(sessionId.uuidString): \(error.localizedDescription)")
                self.runStartupVariants(variants,
                                        at: index + 1,
                                        sessionId: sessionId,
                                        configuration: configuration,
                                        completion: completion)
                return
            }

            let http = response as? HTTPURLResponse
            let body = data ?? Data()
            let contentType = Self.headerValue(named: "Content-Type", in: http)
            let partTypes = Self.readUMPPartTypes(from: body)
            let startResult = SabrSessionStartResult(
                statusCode: http?.statusCode ?? -1,
                contentType: contentType,
                bodySize: body.count,
                umpPartTypes: partTypes,
                rawBody: body,
                responseHeaders: Self.headersMap(from: http),
                followupStatusCode: nil,
                followupContentType: nil,
                followupBodySize: nil,
                followupUMPPartTypes: [],
                followupResponseHeaders: [:],
                followupLabel: nil
            )

            self.queue.async {
                guard var stored = self.sessions[sessionId] else { return }
                stored.requestNumber = index + 1
                stored.lastStartResult = startResult
                self.applyUMPState(body: body, to: &stored)
                self.sessions[sessionId] = stored
                print("[SabrSession] \(variant.label) result \(sessionId.uuidString): status=\(startResult.statusCode) type=\(startResult.contentType ?? "nil") bytes=\(startResult.bodySize) parts=\(startResult.umpPartTypes)")
                print("[SabrSession] \(variant.label) headers \(sessionId.uuidString): \(startResult.responseHeaders)")
                print("[SabrSession] \(variant.label) state \(sessionId.uuidString): playbackCookie=\(stored.playbackCookie?.count ?? 0) activeContexts=\(Array(stored.activeSabrContextTypes).sorted()) nextPolicy=\(stored.nextRequestPolicy != nil)")

                guard startResult.statusCode < 400 else {
                    print("[SabrSession] \(variant.label) rejected with HTTP \(startResult.statusCode), trying next startup variant")
                    self.runStartupVariants(variants,
                                            at: index + 1,
                                            sessionId: sessionId,
                                            configuration: configuration,
                                            completion: completion)
                    return
                }

                let hasState = startResult.bodySize > 0 || !startResult.umpPartTypes.isEmpty || stored.playbackCookie != nil || !stored.activeSabrContextTypes.isEmpty || stored.nextRequestPolicy != nil
                if !hasState {
                    print("[SabrSession] \(variant.label) produced empty accepted response, trying next startup variant")
                    self.runStartupVariants(variants,
                                            at: index + 1,
                                            sessionId: sessionId,
                                            configuration: configuration,
                                            completion: completion)
                    return
                }

                self.sendCurrentProbe(sessionId: sessionId,
                                      configuration: configuration,
                                      sessionState: stored,
                                      bootstrapStyle: variant.bootstrapStyle,
                                      transportProfile: variant.transportProfile,
                                      includeBootstrapHeaders: false,
                                      bodyProfile: variant.bodyProfile) { followup in
                    self.queue.async {
                        guard var refreshed = self.sessions[sessionId] else { return }
                        if let followup {
                            refreshed.lastStartResult = SabrSessionStartResult(
                                statusCode: startResult.statusCode,
                                contentType: startResult.contentType,
                                bodySize: startResult.bodySize,
                                umpPartTypes: startResult.umpPartTypes,
                                rawBody: startResult.rawBody,
                                responseHeaders: startResult.responseHeaders,
                                followupStatusCode: followup.statusCode,
                                followupContentType: followup.contentType,
                                followupBodySize: followup.bodySize,
                                followupUMPPartTypes: followup.umpPartTypes,
                                followupResponseHeaders: followup.responseHeaders,
                                followupLabel: followup.followupLabel
                            )
                            self.applyUMPState(body: followup.rawBody, to: &refreshed)
                            self.sessions[sessionId] = refreshed
                            print("[SabrSession] followup result \(sessionId.uuidString): status=\(followup.statusCode) type=\(followup.contentType ?? "nil") bytes=\(followup.bodySize) parts=\(followup.umpPartTypes)")
                            print("[SabrSession] followup headers \(sessionId.uuidString): \(followup.responseHeaders)")
                            print("[SabrSession] followup state \(sessionId.uuidString): playbackCookie=\(refreshed.playbackCookie?.count ?? 0) activeContexts=\(Array(refreshed.activeSabrContextTypes).sorted()) nextPolicy=\(refreshed.nextRequestPolicy != nil)")
                            completion(.success((refreshed, refreshed.lastStartResult!)))
                        } else {
                            completion(.success((refreshed, refreshed.lastStartResult!)))
                        }
                    }
                }
            }
        }.resume()
    }

    private func sendCurrentProbe(sessionId: UUID,
                                  configuration: SabrSessionConfiguration,
                                  sessionState: SabrSession,
                                  bootstrapStyle: SabrProbeRequest.BootstrapStyle,
                                  transportProfile: SabrProbeRequest.TransportProfile,
                                  includeBootstrapHeaders: Bool,
                                  bodyProfile: SabrProbeRequest.BodyProfile,
                                  completion: @escaping (SabrSessionStartResult?) -> Void) {
        let activeContexts = sessionState.sabrContexts.values
            .filter { sessionState.activeSabrContextTypes.contains($0.type) }
            .sorted { $0.type < $1.type }
        let unsentContextTypes = sessionState.sabrContexts.keys
            .filter { !sessionState.activeSabrContextTypes.contains($0) }
            .sorted()
        let probeFormats: [(String, SabrFormatInfo)] = [
            ("current-video", configuration.videoFormat),
            ("current-audio", configuration.audioFormat)
        ]

        func runProbe(at index: Int) {
            guard index < probeFormats.count else {
                completion(nil)
                return
            }

            let (label, format) = probeFormats[index]
            let requestNumber = nextRequestNumber()
            let currentRequest = SabrProbeRequest(
                streamingURL: configuration.streamingURL,
                ustreamerConfigData: configuration.videoPlaybackUstreamerConfig,
                contentPoToken: configuration.contentPoToken,
                client: configuration.client,
                visitorData: configuration.visitorData,
                audioFormat: configuration.audioFormat,
                videoFormat: configuration.videoFormat,
                bootstrapParts: configuration.bootstrapParts,
                currentFormat: format,
                mode: .current,
                label: label,
                requestNumber: requestNumber,
                contentPlaybackNonce: configuration.contentPlaybackNonce,
                bootstrapStyle: bootstrapStyle,
                includeBootstrapHeaders: includeBootstrapHeaders,
                transportProfile: transportProfile,
                bootstrapHeaderPlacement: .field11,
                bodyProfile: bodyProfile,
                playbackCookie: sessionState.playbackCookie,
                activeSabrContexts: activeContexts,
                unsentSabrContextTypes: unsentContextTypes
            )

            guard let urlRequest = SabrProbeService.shared.buildStartupRequest(from: currentRequest) else {
                runProbe(at: index + 1)
                return
            }

            SabrRequestMetadataStore.shared.setMetadata(
                SabrRequestMetadata(
                    format: format,
                    isSABR: true,
                    isUMP: true,
                    isInitSegment: false,
                    byteRange: nil,
                    timestamp: Date()
                ),
                for: requestNumber
            )

            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    print("[SabrSession] followup failed \(sessionId.uuidString) \(label): \(error.localizedDescription)")
                    runProbe(at: index + 1)
                    return
                }

                let http = response as? HTTPURLResponse
                let body = data ?? Data()
                let result = SabrSessionStartResult(
                    statusCode: http?.statusCode ?? -1,
                    contentType: Self.headerValue(named: "Content-Type", in: http),
                    bodySize: body.count,
                    umpPartTypes: Self.readUMPPartTypes(from: body),
                    rawBody: body,
                    responseHeaders: Self.headersMap(from: http),
                    followupStatusCode: nil,
                    followupContentType: nil,
                    followupBodySize: nil,
                    followupUMPPartTypes: [],
                    followupResponseHeaders: [:],
                    followupLabel: label
                )

                if body.count > 0 || !result.umpPartTypes.isEmpty || result.statusCode >= 400 {
                    completion(result)
                } else {
                    print("[SabrSession] empty followup \(sessionId.uuidString) \(label), trying next probe")
                    runProbe(at: index + 1)
                }
            }.resume()
        }

        runProbe(at: 0)
    }

    func session(id: UUID) -> SabrSession? {
        queue.sync { sessions[id] }
    }

    func clearSession(id: UUID) {
        queue.async {
            self.sessions[id] = nil
        }
    }

    func clearAll() {
        queue.async {
            self.sessions.removeAll()
        }
    }

    private func nextRequestNumber() -> String {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            defer { requestCounter += 1 }
            return String(requestCounter)
        }

        return queue.sync {
            defer { requestCounter += 1 }
            return String(requestCounter)
        }
    }

    private static func readUMPPartTypes(from data: Data) -> [Int] {
        let reader = SabrUMPReader()
        reader.append(data)
        return reader.readAvailableParts(limit: 12).map(\.type)
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

    private static func headersMap(from response: HTTPURLResponse?) -> [String: String] {
        guard let response else { return [:] }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String {
                headers[key] = String(describing: value)
            }
        }
        return headers
    }

    private func applyUMPState(body: Data, to session: inout SabrSession) {
        let reader = SabrUMPReader()
        reader.append(body)
        let parts = reader.readAvailableParts(limit: 64)

        for part in parts {
            switch part.type {
            case 54:
                session.nextRequestPolicy = SabrNextRequestPolicyState(rawPayload: part.payload)
                if let cookie = Self.extractPlaybackCookie(from: part.payload) {
                    session.playbackCookie = cookie
                }
            case 57:
                if let context = Self.extractSabrContext(from: part.payload) {
                    session.sabrContexts[context.type] = context
                    if context.sendByDefault {
                        session.activeSabrContextTypes.insert(context.type)
                    }
                }
            case 58:
                Self.applyContextSendingPolicy(payload: part.payload, to: &session)
            default:
                continue
            }
        }
    }

    private static func extractPlaybackCookie(from payload: Data) -> Data? {
        extractLengthDelimitedField(fieldNumber: 2, from: payload)
    }

    private static func extractSabrContext(from payload: Data) -> SabrContextState? {
        guard let type = extractVarintField(fieldNumber: 1, from: payload),
              let value = extractLengthDelimitedField(fieldNumber: 2, from: payload),
              !value.isEmpty
        else {
            return nil
        }

        let sendByDefault = extractVarintField(fieldNumber: 4, from: payload) == 1
        return SabrContextState(type: type, value: value, sendByDefault: sendByDefault)
    }

    private static func applyContextSendingPolicy(payload: Data, to session: inout SabrSession) {
        extractRepeatedVarintField(fieldNumber: 1, from: payload).forEach { session.activeSabrContextTypes.insert($0) }
        extractRepeatedVarintField(fieldNumber: 2, from: payload).forEach { session.activeSabrContextTypes.remove($0) }
        extractRepeatedVarintField(fieldNumber: 3, from: payload).forEach {
            session.activeSabrContextTypes.remove($0)
            session.sabrContexts[$0] = nil
        }
    }

    private static func extractVarintField(fieldNumber: Int, from data: Data) -> Int? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOffset) = SabrUMPReader.readVarint(from: data, offset: offset) else { return nil }
            let wireType = tag & 0x7
            let currentField = tag >> 3
            offset = nextOffset

            if currentField == fieldNumber, wireType == 0 {
                return SabrUMPReader.readVarint(from: data, offset: offset)?.0
            }

            guard let skipped = skipField(wireType: wireType, in: data, offset: offset) else { return nil }
            offset = skipped
        }
        return nil
    }

    private static func extractRepeatedVarintField(fieldNumber: Int, from data: Data) -> [Int] {
        var values: [Int] = []
        var offset = 0

        while offset < data.count {
            guard let (tag, nextOffset) = SabrUMPReader.readVarint(from: data, offset: offset) else { break }
            let wireType = tag & 0x7
            let currentField = tag >> 3
            offset = nextOffset

            if currentField == fieldNumber {
                switch wireType {
                case 0:
                    if let (value, valueOffset) = SabrUMPReader.readVarint(from: data, offset: offset) {
                        values.append(value)
                        offset = valueOffset
                        continue
                    }
                case 2:
                    if let (length, valueOffset) = SabrUMPReader.readVarint(from: data, offset: offset) {
                        var packedOffset = valueOffset
                        let packedEnd = valueOffset + length
                        while packedOffset < packedEnd,
                              let (value, nextPackedOffset) = SabrUMPReader.readVarint(from: data, offset: packedOffset) {
                            values.append(value)
                            packedOffset = nextPackedOffset
                        }
                        offset = packedEnd
                        continue
                    }
                default:
                    break
                }
            }

            guard let skipped = skipField(wireType: wireType, in: data, offset: offset) else { break }
            offset = skipped
        }

        return values
    }

    private static func extractLengthDelimitedField(fieldNumber: Int, from data: Data) -> Data? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOffset) = SabrUMPReader.readVarint(from: data, offset: offset) else { return nil }
            let wireType = tag & 0x7
            let currentField = tag >> 3
            offset = nextOffset

            if currentField == fieldNumber, wireType == 2 {
                guard let (length, valueOffset) = SabrUMPReader.readVarint(from: data, offset: offset),
                      valueOffset + length <= data.count
                else {
                    return nil
                }
                return data.subdata(in: valueOffset..<(valueOffset + length))
            }

            guard let skipped = skipField(wireType: wireType, in: data, offset: offset) else { return nil }
            offset = skipped
        }
        return nil
    }

    private static func skipField(wireType: Int, in data: Data, offset: Int) -> Int? {
        switch wireType {
        case 0:
            return SabrUMPReader.readVarint(from: data, offset: offset)?.1
        case 2:
            guard let (length, nextOffset) = SabrUMPReader.readVarint(from: data, offset: offset),
                  nextOffset + length <= data.count
            else {
                return nil
            }
            return nextOffset + length
        case 5:
            let end = offset + 4
            return end <= data.count ? end : nil
        case 1:
            let end = offset + 8
            return end <= data.count ? end : nil
        default:
            return nil
        }
    }
}
