import Foundation

extension OAuthClient {
    func fetchClientCredentials(
        completion: @escaping (Result<(String, String), Error>) -> Void
    ) {
        guard let url = URL(string: AppURLs.YouTube.tv) else {
            return
        }
        var request = URLRequest(url: url)
        request.setValue(
            UserAgent.cobaltTV,
            forHTTPHeaderField: HTTPHeader.userAgent
        )
        request.setValue(
            AppURLs.YouTube.tv,
            forHTTPHeaderField: HTTPHeader.referer
        )
        request.setValue(
            "en-US",
            forHTTPHeaderField: HTTPHeader.acceptLanguage
        )
        performRequest(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                self.parseHTMLForScript(
                    data: data,
                    completion: completion
                )
            }
        }
    }
    private func parseHTMLForScript(
        data: Data,
        completion: @escaping (Result<(String, String), Error>) -> Void
    ) {
        guard let html = String(data: data, encoding: .utf8) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        let pattern = #"<script\s+id="base-js"\s+src="([^"]+)""#
        guard let scriptURL = OAuthClient.match(pattern: pattern, in: html, group: 1) else {
            AppLog.auth("Could not find base-js script URL")
            completion(.failure(APIError.decodingFailed))
            return
        }
        let fullURL = scriptURL.hasPrefix("http")
            ? scriptURL
            : "https://www.youtube.com\(scriptURL)"
        guard let jsURL = URL(string: fullURL) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        performRequest(URLRequest(url: jsURL)) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                self.extractCredentials(
                    data: data,
                    completion: completion
                )
            }
        }
    }
    private func extractCredentials(
        data: Data,
        completion: @escaping (Result<(String, String), Error>) -> Void
    ) {
        guard let js = String(data: data, encoding: .utf8) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        let idPat = #"clientId:"([^"]+)""#
        let secPat =
            #"clientId:"[^"]+",\s*\w+:"([^"]+)""#
        guard let clientId = OAuthClient.match(
            pattern: idPat,
            in: js,
            group: 1
        ),
              let clientSecret = OAuthClient.match(
                  pattern: secPat,
                  in: js,
                  group: 1
              )
        else {
            AppLog.auth(
                "Could not extract client credentials"
            )
            completion(.failure(APIError.decodingFailed))
            return
        }
        AppLog.auth(
            "Got client credentials " +
            "(id=\(clientId.prefix(20))...)"
        )
        completion(.success((clientId, clientSecret)))
    }
}
