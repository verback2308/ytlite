import Foundation

// MARK: - Execute Onesie Request

extension OnesieService {
    static func handleOnesieResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (
            Result<OnesiePlaybackBootstrap, Error>
        ) -> Void
    ) {
        if let error {
            AppLog.onesie(
                "request failed: "
                    + error.localizedDescription
            )
            completion(.failure(error))
            return
        }
        let http = response as? HTTPURLResponse
        let body = data ?? Data()
        AppLog.onesie(
            "response "
                + "status=\(http?.statusCode ?? -1)"
                + " bytes=\(body.count)"
        )
        guard let bootstrap = OnesieUMPParser
            .parse(body) else {
            completion(
                .failure(
                    OnesieError.parseError(
                        "UMP response"
                    )
                )
            )
            return
        }
        completion(.success(bootstrap))
    }
}

// MARK: - Payload Building

extension OnesieService {
    func executeOnesie(
        params: OnesieRequestParams,
        completion: @escaping (
            Result<OnesiePlaybackBootstrap, Error>
        ) -> Void
    ) {
        guard let payload = buildOnesiePayload(
            params: params
        ) else {
            completion(
                .failure(OnesieError.encodeError)
            )
            return
        }
        sendOnesieRequest(
            params: params,
            payload: payload,
            completion: completion
        )
    }

    func sendOnesieRequest(
        params: OnesieRequestParams,
        payload: Data,
        completion: @escaping (
            Result<OnesiePlaybackBootstrap, Error>
        ) -> Void
    ) {
        guard let url = buildOnesieURL(
            params: params
        ) else {
            completion(
                .failure(OnesieError.invalidURL)
            )
            return
        }
        let request = configureOnesieRequest(
            url: url,
            body: payload,
            params: params
        )
        AppLog.onesie(
            "POST "
                + "\(url.absoluteString.prefix(80))"
        )
        let task = URLSession.shared.dataTask(
            with: request
        ) { data, response, error in
            Self.handleOnesieResponse(
                data: data,
                response: response,
                error: error,
                completion: completion
            )
        }
        task.resume()
    }

    func buildOnesiePayload(
        params: OnesieRequestParams
    ) -> Data? {
        guard let bodyStr = buildInnertubeJSON(
            params: params
        ) else {
            return nil
        }
        let innerReq = buildInnerRequest(
            params: params,
            bodyString: bodyStr
        )
        return assembleOnesieRequest(
            innerReq: innerReq,
            config: params.config
        )
    }

    func buildInnertubeJSON(
        params: OnesieRequestParams
    ) -> String? {
        let sid: [String: Any] =
            params.poToken.map {
                ["poToken": $0]
            } ?? [:]
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "TVHTML5",
                    "clientVersion":
                        "7.20260311.12.00",
                    "hl": "en",
                    "gl": "US",
                    "visitorData":
                        params.visitorData
                ]
            ],
            "videoId": params.videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "serviceIntegrityDimensions": sid
        ]
        guard let data = try? JSONSerialization
            .data(withJSONObject: body) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
