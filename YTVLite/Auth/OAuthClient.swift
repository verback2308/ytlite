import Foundation

final class OAuthClient {
    struct DeviceCodeResponse {
        let deviceCode: String
        let userCode: String
        let verificationURL: String
        let interval: Int
        let clientId: String
        let clientSecret: String
    }
    struct PollConfig {
        let deviceCode: String
        let clientId: String
        let clientSecret: String
        let interval: Int
    }
    static let shared = OAuthClient()
    private let deviceCodeURL = AppURLs.YouTubeOAuth.deviceCode
    let tokenURL = AppURLs.YouTubeOAuth.token
    private let scope =
        "http://gdata.youtube.com " +
        "https://www.googleapis.com/auth/youtube-paid-content"
    let keychainService = "com.ytvlite.oauth"
    let keychainAccount = "youtube"
    var tokens: OAuthTokens?
    var isSignedIn: Bool { tokens != nil }
    var isAnonymous: Bool {
        get {
            tokens == nil && UserDefaults.standard.bool(
                forKey: UserDefaultsKeys.Auth.isAnonymous
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: UserDefaultsKeys.Auth.isAnonymous
            )
        }
    }
    private init() {
        tokens = loadFromKeychain()
    }
}

extension OAuthClient {
    static func match(
        pattern: String,
        in string: String,
        group: Int
    ) -> String? {
        let fullRange = NSRange(string.startIndex..., in: string)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: string, range: fullRange),
              let range = Range(result.range(at: group), in: string)
        else {
            return nil
        }
        return String(string[range])
    }
    func makePostRequest(
        urlString: String,
        body: [String: Any]
    ) -> URLRequest? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            HTTPHeaderValue.contentTypeJSON,
            forHTTPHeaderField: HTTPHeader.contentType
        )
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: body
        )
        return request
    }
    func performRequest(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let task = URLSession.shared.dataTask(
            with: request
        ) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(APIError.decodingFailed))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }
}

extension OAuthClient {
    func requestDeviceCode(
        completion: @escaping (Result<DeviceCodeResponse, Error>) -> Void
    ) {
        fetchClientCredentials { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (clientId, clientSecret)):
                self.doRequestDeviceCode(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    completion: completion
                )
            }
        }
    }
    private func doRequestDeviceCode(
        clientId: String,
        clientSecret: String,
        completion: @escaping (Result<DeviceCodeResponse, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "client_id": clientId,
            "scope": scope,
            "device_id": UUID().uuidString,
            "device_model": "ytlr::"
        ]
        guard let request = makePostRequest(
            urlString: deviceCodeURL,
            body: body
        ) else {
            return
        }
        performRequest(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                self.parseDeviceCodeResponse(
                    data: data,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    completion: completion
                )
            }
        }
    }
    private func parseDeviceCodeResponse(
        data: Data,
        clientId: String,
        clientSecret: String,
        completion: @escaping (Result<DeviceCodeResponse, Error>) -> Void
    ) {
        guard let json = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verURL = json["verification_url"] as? String,
              let interval = json["interval"] as? Int
        else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            AppLog.auth("requestDeviceCode failed: \(raw)")
            completion(.failure(APIError.decodingFailed))
            return
        }
        let response = DeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verURL,
            interval: interval,
            clientId: clientId,
            clientSecret: clientSecret
        )
        completion(.success(response))
    }
}

extension OAuthClient {
    func validToken(
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let tokens else {
            if !isAnonymous {
                NotificationCenter.default.post(
                    name: .authorizationRequired,
                    object: nil
                )
            }
            completion(.failure(APIError.unauthorized))
            return
        }
        if !tokens.isExpired {
            AppLog.auth(
                "Using cached token: " +
                "\(tokens.accessToken.prefix(16))..."
            )
            completion(.success(tokens.accessToken))
            return
        }
        doRefresh(tokens: tokens, completion: completion)
    }
    private func doRefresh(
        tokens: OAuthTokens,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "client_id": tokens.clientId,
            "client_secret": tokens.clientSecret,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        guard let request = makePostRequest(
            urlString: tokenURL,
            body: body
        ) else {
            return
        }
        performRequest(request) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                self?.handleRefreshResponse(
                    data: data,
                    tokens: tokens,
                    completion: completion
                )
            }
        }
    }
    private func handleRefreshResponse(
        data: Data,
        tokens: OAuthTokens,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let json = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        var updated = tokens
        updated.accessToken = accessToken
        updated.expiryDate = Date().addingTimeInterval(
            TimeInterval(expiresIn)
        )
        self.tokens = updated
        saveToKeychain(updated)
        AppLog.auth(
            "Token refreshed: \(accessToken.prefix(16))..."
        )
        completion(.success(accessToken))
    }
    func signOut() {
        tokens = nil
        isAnonymous = false
        deleteFromKeychain()
    }
}
