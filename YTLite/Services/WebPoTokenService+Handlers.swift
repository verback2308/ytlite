import Foundation
import WebKit

// MARK: - WKScriptMessageHandler

extension WebPoTokenService: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body
            as? [String: Any],
              let identifier = body["identifier"]
                  as? String
        else {
            return
        }
        let attemptID = body["attemptID"] as? String
        guard isCurrentAttempt(
            identifier: identifier,
            attemptID: attemptID
        ) else {
            logStaleMessage(
                name: message.name, body: body
            )
            return
        }
        dispatchMessage(
            name: message.name,
            identifier: identifier,
            attemptID: attemptID,
            body: body
        )
    }
}

// MARK: - Message Dispatch

extension WebPoTokenService {
    private func logStaleMessage(
        name: String,
        body: [String: Any]
    ) {
        if let text = body["message"] as? String {
            AppLog.poToken(
                "ignoring stale \(name): \(text)"
            )
        } else {
            AppLog.poToken(
                "ignoring stale \(name)"
            )
        }
    }

    private func dispatchMessage(
        name: String,
        identifier: String,
        attemptID: String?,
        body: [String: Any]
    ) {
        switch name {
        case "webPoToken":
            handleTokenMessage(
                identifier: identifier,
                body: body
            )
        case "webPoError":
            handleErrorMessage(
                identifier: identifier,
                body: body
            )
        case "webPoGenerateIT":
            handleGenerateITMessage(
                identifier: identifier,
                attemptID: attemptID,
                body: body
            )
        case "webPoLog":
            handleLogMessage(body: body)
        default:
            break
        }
    }

    private func handleTokenMessage(
        identifier: String,
        body: [String: Any]
    ) {
        if let token = body["token"] as? String,
           !token.isEmpty {
            resolve(
                identifier: identifier,
                result: .success(token)
            )
        } else {
            resolve(
                identifier: identifier,
                result: .failure(
                    ServiceError.invalidMessage
                )
            )
        }
    }

    private func handleErrorMessage(
        identifier: String,
        body: [String: Any]
    ) {
        let text = body["message"] as? String
            ?? "Unknown WebPO error"
        resolve(
            identifier: identifier,
            result: .failure(
                ServiceError.mintFailed(text)
            )
        )
    }

    private func handleGenerateITMessage(
        identifier: String,
        attemptID: String?,
        body: [String: Any]
    ) {
        if let response =
            body["botguardResponse"] as? String,
           !response.isEmpty {
            startGenerateIT(
                identifier: identifier,
                attemptID: attemptID,
                botguardResponse: response
            )
        } else {
            resolve(
                identifier: identifier,
                result: .failure(
                    ServiceError.invalidMessage
                )
            )
        }
    }

    private func handleLogMessage(
        body: [String: Any]
    ) {
        if let text = body["message"] as? String {
            AppLog.poToken("\(text)")
        }
    }
}

// MARK: - Script Evaluation

extension WebPoTokenService {
    func isCurrentAttempt(
        identifier: String,
        attemptID: String?
    ) -> Bool {
        queue.sync {
            guard let activeID =
                activeAttemptIDs[identifier],
                  let attemptID
            else {
                return false
            }
            return activeID == attemptID
        }
    }

    func evaluateScript(
        _ script: String,
        identifier: String,
        attemptID: String?
    ) {
        webView.evaluateJavaScript(
            script
        ) { _, err in
            guard let err else {
                return
            }
            let isCurrent = self.isCurrentAttempt(
                identifier: identifier,
                attemptID: attemptID
            )
            guard isCurrent else {
                AppLog.poToken(
                    "ignoring stale eval error: "
                    + err.localizedDescription
                )
                return
            }
            self.resolve(
                identifier: identifier,
                result: .failure(err)
            )
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPoTokenService: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation?
    ) {
        queue.async {
            self.isLoaded = true
            let callbacks = self.loadCallbacks
            self.loadCallbacks.removeAll()
            DispatchQueue.main.async {
                callbacks.forEach { $0() }
            }
        }
    }
}
