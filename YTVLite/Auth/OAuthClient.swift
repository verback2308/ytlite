import Foundation

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiryDate: Date
    var clientId: String
    var clientSecret: String
    var isExpired: Bool { expiryDate.timeIntervalSinceNow < 60 }
}

extension Notification.Name {
    static let authorizationRequired = Notification.Name("authorizationRequired")
    static let userDidSignOut = Notification.Name("userDidSignOut")
}

final class OAuthClient {
    static let shared = OAuthClient()

    private let deviceCodeURL = AppURLs.YouTube.OAuth.deviceCode
    private let tokenURL      = AppURLs.YouTube.OAuth.token
    private let scope         = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"

    private(set) var tokens: OAuthTokens?
    var isSignedIn: Bool { tokens != nil }

    var isAnonymous: Bool {
        get { tokens == nil && UserDefaults.standard.bool(forKey: UserDefaultsKeys.Auth.isAnonymous) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.Auth.isAnonymous) }
    }

    private init() { tokens = loadFromKeychain() }

    // MARK: - Device flow

    struct DeviceCodeResponse {
        let deviceCode: String
        let userCode: String
        let verificationURL: String
        let interval: Int
        let clientId: String
        let clientSecret: String
    }

    func requestDeviceCode(completion: @escaping (Result<DeviceCodeResponse, Error>) -> Void) {
        fetchClientCredentials { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let (clientId, clientSecret)):
                self.doRequestDeviceCode(clientId: clientId, clientSecret: clientSecret, completion: completion)
            }
        }
    }

    private func doRequestDeviceCode(clientId: String, clientSecret: String,
                                     completion: @escaping (Result<DeviceCodeResponse, Error>) -> Void) {
        guard let url = URL(string: deviceCodeURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_id": clientId,
            "scope": scope,
            "device_id": UUID().uuidString,
            "device_model": "ytlr::"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceCode = json["device_code"] as? String,
                  let userCode = json["user_code"] as? String,
                  let verificationURL = json["verification_url"] as? String,
                  let interval = json["interval"] as? Int
            else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                print("[OAuth] requestDeviceCode failed: \(raw)")
                completion(.failure(APIError.decodingFailed)); return
            }
            completion(.success(DeviceCodeResponse(deviceCode: deviceCode, userCode: userCode,
                                                   verificationURL: verificationURL, interval: interval,
                                                   clientId: clientId, clientSecret: clientSecret)))
        }.resume()
    }

    func pollForToken(deviceCode: String, clientId: String, clientSecret: String,
                      interval: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(interval)) { [weak self] in
            self?.exchangeToken(deviceCode: deviceCode, clientId: clientId, clientSecret: clientSecret,
                                interval: interval, completion: completion)
        }
    }

    private func exchangeToken(deviceCode: String, clientId: String, clientSecret: String,
                                interval: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: tokenURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": deviceCode,
            "grant_type": "http://oauth.net/grant_type/device/1.0"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(.failure(APIError.decodingFailed)); return }
            if let accessToken = json["access_token"] as? String,
               let refreshToken = json["refresh_token"] as? String,
               let expiresIn = json["expires_in"] as? Int {
                let t = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken,
                                    expiryDate: Date().addingTimeInterval(TimeInterval(expiresIn)),
                                    clientId: clientId, clientSecret: clientSecret)
                self?.tokens = t
                self?.saveToKeychain(t)
                AppLog.auth("New token obtained: \(accessToken)")
                completion(.success(()))
            } else if (json["error"] as? String) == "authorization_pending" {
                self?.pollForToken(deviceCode: deviceCode, clientId: clientId, clientSecret: clientSecret,
                                   interval: interval, completion: completion)
            } else if (json["error"] as? String) == "slow_down" {
                self?.pollForToken(deviceCode: deviceCode, clientId: clientId, clientSecret: clientSecret,
                                   interval: interval + 5, completion: completion)
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "nil"
                print("[OAuth] exchangeToken failed: \(raw)")
                completion(.failure(APIError.decodingFailed))
            }
        }.resume()
    }

    // MARK: - Token management

    func validToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let tokens = tokens else {
            if !isAnonymous {
                NotificationCenter.default.post(name: .authorizationRequired, object: nil)
            }
            completion(.failure(APIError.unauthorized))
            return
        }
        if !tokens.isExpired {
            AppLog.auth("Using cached token: \(tokens.accessToken)")
            completion(.success(tokens.accessToken)); return
        }
        doRefresh(tokens: tokens, completion: completion)
    }

    private func doRefresh(tokens: OAuthTokens, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: tokenURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_id": tokens.clientId,
            "client_secret": tokens.clientSecret,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int
            else { completion(.failure(APIError.decodingFailed)); return }
            var updated = tokens
            updated.accessToken = accessToken
            updated.expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            self?.tokens = updated
            self?.saveToKeychain(updated)
            AppLog.auth("Token refreshed: \(accessToken)")
            completion(.success(accessToken))
        }.resume()
    }

    func signOut() {
        tokens = nil
        isAnonymous = false
        deleteFromKeychain()
    }

    // MARK: - Fetch client credentials from YouTube TV page

    private func fetchClientCredentials(completion: @escaping (Result<(String, String), Error>) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/tv") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/tv", forHTTPHeaderField: "Referer")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(.failure(APIError.decodingFailed)); return
            }
            // Find base-js script URL
            guard let scriptURL = OAuthClient.match(pattern: #"<script\s+id="base-js"\s+src="([^"]+)""#,
                                                     in: html, group: 1)
            else {
                print("[OAuth] Could not find base-js script URL")
                completion(.failure(APIError.decodingFailed)); return
            }
            let fullScriptURL = scriptURL.hasPrefix("http") ? scriptURL : "https://www.youtube.com\(scriptURL)"
            guard let jsURL = URL(string: fullScriptURL) else {
                completion(.failure(APIError.decodingFailed)); return
            }
            URLSession.shared.dataTask(with: jsURL) { data, _, error in
                if let error = error { completion(.failure(error)); return }
                guard let data = data, let js = String(data: data, encoding: .utf8) else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                guard let clientId = OAuthClient.match(pattern: #"clientId:"([^"]+)""#, in: js, group: 1),
                      let clientSecret = OAuthClient.match(pattern: #"clientId:"[^"]+",\s*\w+:"([^"]+)""#, in: js, group: 1)
                else {
                    print("[OAuth] Could not extract client credentials from TV script")
                    completion(.failure(APIError.decodingFailed)); return
                }
                print("[OAuth] Got client credentials (id=\(clientId.prefix(20))...)")
                completion(.success((clientId, clientSecret)))
            }.resume()
        }.resume()
    }

    private static func match(pattern: String, in string: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: group), in: string)
        else { return nil }
        return String(string[range])
    }

    // MARK: - Keychain

    private let keychainService = "com.ytvlite.oauth"
    private let keychainAccount = "youtube"

    private func saveToKeychain(_ tokens: OAuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadFromKeychain() -> OAuthTokens? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
    }
}
