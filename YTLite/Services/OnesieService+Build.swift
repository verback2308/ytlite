import Foundation

// MARK: - Protobuf Request Building

extension OnesieService {
    static func protoHeader(
        name: String,
        value: String
    ) -> Data {
        var header = Data()
        OnesieProtobuf.appendString(
            1, value: name, to: &header
        )
        OnesieProtobuf.appendString(
            2, value: value, to: &header
        )
        return header
    }

    func buildInnerRequest(
        params: OnesieRequestParams,
        bodyString: String
    ) -> Data {
        let playerURL =
            "https://youtubei.googleapis.com"
            + "/youtubei/v1/player"
            + "?key=AIzaSyDCU8hByM-4DrUqRUYnGn"
            + "-3llEO78bcxq8"
        var proto = Data()
        OnesieProtobuf.appendString(
            1, value: playerURL, to: &proto
        )
        appendHTTPHeaders(
            params: params, to: &proto
        )
        OnesieProtobuf.appendString(
            3, value: bodyString, to: &proto
        )
        OnesieProtobuf.appendBool(
            4, value: true, to: &proto
        )
        OnesieProtobuf.appendBool(
            6, value: true, to: &proto
        )
        return proto
    }

    func appendHTTPHeaders(
        params: OnesieRequestParams,
        to proto: inout Data
    ) {
        let ct = Self.protoHeader(
            name: HTTPHeader.contentType,
            value: HTTPHeaderValue.contentTypeJSON
        )
        OnesieProtobuf.appendBytes(
            2, payload: ct, to: &proto
        )
        if !params.visitorData.isEmpty {
            let vh = Self.protoHeader(
                name: HTTPHeader.xGoogVisitorId,
                value: params.visitorData
            )
            OnesieProtobuf.appendBytes(
                2, payload: vh, to: &proto
            )
        }
        if let auth = params.authToken,
           !auth.isEmpty {
            let ah = Self.protoHeader(
                name: HTTPHeader.authorization,
                value: "Bearer \(auth)"
            )
            OnesieProtobuf.appendBytes(
                2, payload: ah, to: &proto
            )
        }
    }
}

// MARK: - Encryption & Assembly

extension OnesieService {
    func encryptAndWrap(
        innerRequest: Data,
        config: OnesieHotConfig
    ) -> Data? {
        guard let enc = OnesieCrypto
            .encryptAesCtrHmac(
                data: innerRequest,
                clientKeyData: config.clientKeyData
            ) else {
            return nil
        }
        return buildWrappedMessage(
            enc: enc, config: config
        )
    }

    func buildWrappedMessage(
        enc: OnesieEncryptedData,
        config: OnesieHotConfig
    ) -> Data {
        var msg = Data()
        let ek = config.encryptedClientKey
        OnesieProtobuf.appendBytes(
            2, payload: enc.ciphertext, to: &msg
        )
        OnesieProtobuf.appendBytes(
            5, payload: ek, to: &msg
        )
        OnesieProtobuf.appendBytes(
            6, payload: enc.iv, to: &msg
        )
        OnesieProtobuf.appendBytes(
            7, payload: enc.hmac, to: &msg
        )
        OnesieProtobuf.appendBool(
            10, value: true, to: &msg
        )
        OnesieProtobuf.appendBool(
            14, value: false, to: &msg
        )
        var uFlags = Data()
        OnesieProtobuf.appendBool(
            2, value: false, to: &uFlags
        )
        OnesieProtobuf.appendBytes(
            15, payload: uFlags, to: &msg
        )
        return msg
    }

    func assembleOnesieRequest(
        innerReq: Data,
        config: OnesieHotConfig
    ) -> Data? {
        guard let wrapped = encryptAndWrap(
            innerRequest: innerReq,
            config: config
        ) else {
            return nil
        }
        let ctx = buildStreamerContext()
        var req = Data()
        OnesieProtobuf.appendBytes(
            3, payload: wrapped, to: &req
        )
        OnesieProtobuf.appendBytes(
            4,
            payload: config.onesieUstreamerConfig,
            to: &req
        )
        OnesieProtobuf.appendBytes(
            10, payload: ctx, to: &req
        )
        return req
    }

    func buildStreamerContext() -> Data {
        var clientInfo = Data()
        OnesieProtobuf.appendInt32(
            16, value: 7, to: &clientInfo
        )
        OnesieProtobuf.appendString(
            17,
            value: "7.20260311.12.00",
            to: &clientInfo
        )
        var ctx = Data()
        OnesieProtobuf.appendBytes(
            1, payload: clientInfo, to: &ctx
        )
        return ctx
    }
}

// MARK: - URL & Request Configuration

extension OnesieService {
    func buildOnesieURL(
        params: OnesieRequestParams
    ) -> URL? {
        let idHex = OnesieCrypto.encodeVideoId(
            params.videoId
        )
        var urlStr = params.redirectorHost
            + params.config.baseUrl
            + "&id=\(idHex)"
            + "&cmo:sensitive_content=yes"
            + "&opr=1&osts=0&por=1&rn=1"
        if let cpn = params.contentPlaybackNonce,
           !cpn.isEmpty {
            urlStr += "&cpn=\(cpn)"
        }
        return URL(string: urlStr)
    }

    func configureOnesieRequest(
        url: URL,
        body: Data,
        params: OnesieRequestParams
    ) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 30
        setOnesieHeaders(
            on: &req, params: params
        )
        return req
    }

    func setOnesieHeaders(
        on req: inout URLRequest,
        params: OnesieRequestParams
    ) {
        setContentHeaders(on: &req)
        setIdentityHeaders(
            on: &req, params: params
        )
    }

    func setContentHeaders(
        on req: inout URLRequest
    ) {
        let hdr = HTTPHeader.self
        req.setValue(
            "application/x-protobuf",
            forHTTPHeaderField: hdr.contentType
        )
        req.setValue(
            "application/vnd.yt-ump",
            forHTTPHeaderField: hdr.accept
        )
        req.setValue(
            "gzip, deflate, br",
            forHTTPHeaderField: hdr.acceptEncoding
        )
        req.setValue(
            UserAgent.cobaltTV,
            forHTTPHeaderField: hdr.userAgent
        )
    }

    func setIdentityHeaders(
        on req: inout URLRequest,
        params: OnesieRequestParams
    ) {
        let hdr = HTTPHeader.self
        req.setValue(
            AppURLs.YouTube.base,
            forHTTPHeaderField: hdr.origin
        )
        req.setValue(
            AppURLs.YouTube.tv,
            forHTTPHeaderField: hdr.referer
        )
        req.setValue(
            AppURLs.YouTube.base,
            forHTTPHeaderField: hdr.xOrigin
        )
        req.setValue(
            "7",
            forHTTPHeaderField: hdr.xYoutubeClientName
        )
        req.setValue(
            "7.20260311.12.00",
            forHTTPHeaderField: hdr.xYoutubeClientVersion
        )
        req.setValue(
            params.visitorData,
            forHTTPHeaderField: hdr.xGoogVisitorId
        )
    }
}
