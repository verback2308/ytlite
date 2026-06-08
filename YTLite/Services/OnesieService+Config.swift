import Foundation

// MARK: - Hot Config Fetch

extension OnesieService {
    func fetchHotConfig(
        completion: @escaping (
            Result<OnesieHotConfig, Error>
        ) -> Void
    ) {
        queue.async { [weak self] in
            if let cached = self?.cachedConfig,
               cached.isValid {
                completion(.success(cached))
                return
            }
            self?.sendTvConfigRequest(
                completion: completion
            )
        }
    }

    func sendTvConfigRequest(
        completion: @escaping (
            Result<OnesieHotConfig, Error>
        ) -> Void
    ) {
        let path = "https://www.youtube.com/tv_config"
            + "?action_get_config=true"
            + "&client=lb4&theme=cl"
        guard let url = URL(string: path) else {
            completion(
                .failure(OnesieError.invalidURL)
            )
            return
        }
        var req = URLRequest(url: url)
        req.setValue(
            UserAgent.cobaltTV,
            forHTTPHeaderField: HTTPHeader.userAgent
        )
        req.timeoutInterval = 15
        let task = URLSession.shared.dataTask(
            with: req
        ) { [weak self] data, _, error in
            self?.handleTvConfigResponse(
                data: data,
                error: error,
                completion: completion
            )
        }
        task.resume()
    }

    func handleTvConfigResponse(
        data: Data?,
        error: Error?,
        completion: @escaping (
            Result<OnesieHotConfig, Error>
        ) -> Void
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data, data.count > 4 else {
            completion(
                .failure(OnesieError.invalidResponse)
            )
            return
        }
        guard let config = parseTvConfigData(
            data.dropFirst(4)
        ) else {
            AppLog.onesie("tv_config parse failed")
            completion(
                .failure(
                    OnesieError.parseError(
                        "tv_config structure"
                    )
                )
            )
            return
        }
        cacheTvConfig(config)
        completion(.success(config))
    }

    func cacheTvConfig(_ config: OnesieHotConfig) {
        AppLog.onesie(
            "hot config OK: "
                + "baseUrl=\(config.baseUrl) "
                + "keyExpires="
                + "\(config.keyExpiresInSeconds)s"
        )
        queue.async { [weak self] in
            self?.cachedConfig = config
        }
    }

    func parseTvConfigData(
        _ jsonData: Data
    ) -> OnesieHotConfig? {
        guard
            let json = try? JSONSerialization
                .jsonObject(
                    with: jsonData
                ) as? [String: Any],
            let wpcc = json[
                "webPlayerContextConfig"
            ] as? [String: Any],
            let lr = wpcc[
                "WEB_PLAYER_CONTEXT_CONFIG_"
                    + "ID_LIVING_ROOM_WATCH"
            ] as? [String: Any],
            let hc = lr["onesieHotConfig"]
                as? [String: Any]
        else {
            return nil
        }
        return extractHotConfig(from: hc)
    }

    func extractHotConfig(
        from hc: [String: Any]
    ) -> OnesieHotConfig? {
        guard
            let ckB64 = hc["clientKey"]
                as? String,
            let ekB64 = hc["encryptedClientKey"]
                as? String,
            let usB64 = hc["onesieUstreamerConfig"]
                as? String,
            let baseUrl = hc["baseUrl"]
                as? String,
            let ckData = OnesieCrypto
                .decodeWebSafeBase64(ckB64),
            let ekData = OnesieCrypto
                .decodeWebSafeBase64(ekB64),
            let usData = OnesieCrypto
                .decodeWebSafeBase64(usB64)
        else {
            return nil
        }
        let expires = hc["keyExpiresInSeconds"]
            as? Int ?? 3_600
        return OnesieHotConfig(
            clientKeyData: ckData,
            encryptedClientKey: ekData,
            onesieUstreamerConfig: usData,
            baseUrl: baseUrl,
            keyExpiresInSeconds: expires,
            fetchedAt: Date()
        )
    }
}

// MARK: - Redirector Fetch

extension OnesieService {
    func fetchRedirectorHost(
        completion: @escaping (
            Result<String, Error>
        ) -> Void
    ) {
        queue.async { [weak self] in
            if let cached = self?.cachedRedirectorHost {
                completion(.success(cached))
                return
            }
            self?.sendRedirectorRequest(
                completion: completion
            )
        }
    }

    func sendRedirectorRequest(
        completion: @escaping (
            Result<String, Error>
        ) -> Void
    ) {
        let randId = Int.random(in: 0..<100_000)
        let urlStr =
            "https://redirector.googlevideo.com"
            + "/initplayback?source=youtube"
            + "&itag=0&pvi=0&pai=0&owc=yes"
            + "&cmo:sensitive_content=yes"
            + "&alr=yes&id=\(randId)"
        guard let url = URL(string: urlStr) else {
            completion(
                .failure(OnesieError.invalidURL)
            )
            return
        }
        let task = URLSession.shared.dataTask(
            with: url
        ) { [weak self] data, _, error in
            self?.handleRedirectorResponse(
                data: data,
                error: error,
                completion: completion
            )
        }
        task.resume()
    }

    func handleRedirectorResponse(
        data: Data?,
        error: Error?,
        completion: @escaping (
            Result<String, Error>
        ) -> Void
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let host = parseRedirectorHost(
            data: data
        ) else {
            completion(
                .failure(
                    OnesieError.invalidRedirector
                )
            )
            return
        }
        AppLog.onesie(
            "redirector host: \(host)"
        )
        queue.async { [weak self] in
            self?.cachedRedirectorHost = host
        }
        completion(.success(host))
    }

    func parseRedirectorHost(
        data: Data?
    ) -> String? {
        guard
            let data,
            let text = String(
                data: data,
                encoding: .utf8
            )?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            text.hasPrefix("https://")
        else {
            return nil
        }
        return text.components(
            separatedBy: "/initplayback"
        ).first ?? text
    }
}
