import Foundation
import WebKit

private let webPoResetHTML = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" \
content="width=device-width, initial-scale=1">
  <title>YTLite WebPO</title>
</head>
<body></body>
</html>
"""

final class WebPoTokenService: NSObject {
    struct CachedToken {
        let token: String
        let createdAt: Date
    }

    struct PendingRequest {
        let identifier: String
        let retryCount: Int
        let completion: (Result<String, Error>) -> Void
    }

    enum ServiceError: Error {
        case webViewNotReady
        case invalidMessage
        case mintFailed(String)
        case generateITFailed(String)
        case timedOut(String)
    }

    static let shared = WebPoTokenService()

    let requestKey = "O43z0dpjhgX20SCx4KAo"
    let mintTimeout: TimeInterval = 15
    let maxRetryCount = 1
    let tokenCacheLifetime: TimeInterval =
        60 * 60 * 10
    let staleFallbackLifetime: TimeInterval =
        60 * 60 * 24
    let tokenCacheDefaultsKey =
        "WebPoTokenService.tokenCache"
    let queue = DispatchQueue(
        label: "com.ytvlite.webpo-token-service"
    )
    var tokenCache: [String: CachedToken] = [:]
    var pending: [String: [PendingRequest]] = [:]
    var timeoutWorkItems: [String: DispatchWorkItem] =
        [:]
    var activeAttemptIDs: [String: String] = [:]
    var isLoaded = false
    var loadCallbacks: [() -> Void] = []

    lazy var webView: WKWebView = {
        let ctrl = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = ctrl
        config.applicationNameForUserAgent =
            UserAgent.safariMac
        let view = WKWebView(
            frame: .zero, configuration: config
        )
        view.isHidden = true
        view.navigationDelegate = self
        ctrl.add(self, name: "webPoToken")
        ctrl.add(self, name: "webPoError")
        ctrl.add(self, name: "webPoLog")
        ctrl.add(self, name: "webPoGenerateIT")
        return view
    }()

    override private init() {
        super.init()
        loadPersistedCache()
        DispatchQueue.main.async { [weak self] in
            self?.loadIfNeeded()
        }
    }
}

// MARK: - Core Operations

extension WebPoTokenService {
    func fetchSessionToken(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            if let cached = self.validCachedToken(
                for: identifier
            ) {
                AppLog.poToken(
                    "cache hit for content token"
                )
                DispatchQueue.main.async {
                    completion(
                        .success(cached.token)
                    )
                }
                return
            }
            self.enqueueMint(
                identifier: identifier,
                completion: completion
            )
        }
    }

    private func enqueueMint(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let request = PendingRequest(
            identifier: identifier,
            retryCount: 0,
            completion: completion
        )
        pending[identifier, default: []]
            .append(request)
        let count =
            pending[identifier]?.count ?? 0
        if count > 1 {
            AppLog.poToken(
                "joined pending mint"
            )
            return
        }
        scheduleTimeout(for: identifier)
        DispatchQueue.main.async {
            AppLog.poToken(
                "scheduling mint attempt=0"
            )
            self.ensureReady {
                self.runMint(
                    identifier: identifier
                )
            }
        }
    }

    func loadIfNeeded() {
        guard !isLoaded else {
            return
        }
        guard webView.url == nil else {
            return
        }
        webView.loadHTMLString(
            webPoResetHTML,
            baseURL: URL(
                string: AppURLs.YouTube.base
            )
        )
    }

    func ensureReady(
        _ completion: @escaping () -> Void
    ) {
        if isLoaded {
            completion()
            return
        }
        loadCallbacks.append(completion)
        loadIfNeeded()
    }
}

// MARK: - Mint Execution

extension WebPoTokenService {
    func runMint(identifier: String) {
        guard let idLit =
            jsStringLiteral(identifier),
              let keyLit =
                  jsStringLiteral(requestKey)
        else {
            failMint(identifier: identifier)
            return
        }
        let attemptID = UUID().uuidString
        guard let aidLit =
            jsStringLiteral(attemptID)
        else {
            failMint(identifier: identifier)
            return
        }
        queue.async {
            self.activeAttemptIDs[identifier] = attemptID
        }
        AppLog.poToken("mint start")
        let script = WebPoTokenScripts.mintScript(
            identifier: idLit,
            attemptID: aidLit,
            requestKey: keyLit,
            apiKey: YouTubeCredentials.tvApiKey
        )
        evaluateScript(
            script,
            identifier: identifier,
            attemptID: attemptID
        )
    }

    private func failMint(
        identifier: String
    ) {
        resolve(
            identifier: identifier,
            result: .failure(
                ServiceError.invalidMessage
            )
        )
    }
}

// MARK: - Timeout & Utilities

extension WebPoTokenService {
    func scheduleTimeout(
        for identifier: String
    ) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            let secs = Int(self.mintTimeout)
            self.resolve(
                identifier: identifier,
                result: .failure(
                    ServiceError.timedOut(
                        "WebPO mint timed out "
                        + "after \(secs)s"
                    )
                )
            )
        }
        timeoutWorkItems[identifier] = item
        queue.asyncAfter(
            deadline: .now() + mintTimeout,
            execute: item
        )
    }

    func jsStringLiteral(
        _ value: String
    ) -> String? {
        guard let data =
            try? JSONSerialization.data(
                withJSONObject: [value],
                options: []
            ),
              let json = String(
                  data: data, encoding: .utf8
              ),
              json.count >= 2
        else {
            return nil
        }
        return String(
            json.dropFirst().dropLast()
        )
    }

    func resetWebViewState() {
        DispatchQueue.main.async {
            self.webView.stopLoading()
            self.isLoaded = false
            self.loadCallbacks.removeAll()
            self.webView.loadHTMLString(
                webPoResetHTML,
                baseURL: URL(
                    string: AppURLs.YouTube.base
                )
            )
        }
    }
}
