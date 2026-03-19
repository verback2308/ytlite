import Foundation
import WebKit

final class WebPoTokenService: NSObject {
    static let shared = WebPoTokenService()

    private struct CachedToken {
        let token: String
        let createdAt: Date
    }

    private struct PendingRequest {
        let identifier: String
        let retryCount: Int
        let completion: (Result<String, Error>) -> Void
    }

    private enum ServiceError: Error {
        case webViewNotReady
        case invalidMessage
        case mintFailed(String)
        case generateITFailed(String)
        case timedOut(String)
    }

    private let requestKey = "O43z0dpjhgX20SCx4KAo"
    private let mintTimeout: TimeInterval = 15
    private let maxRetryCount = 1
    private let tokenCacheLifetime: TimeInterval = 60 * 60 * 10
    private let staleFallbackLifetime: TimeInterval = 60 * 60 * 24
    private let tokenCacheDefaultsKey = "WebPoTokenService.tokenCache"
    private let queue = DispatchQueue(label: "com.ytvlite.webpo-token-service")
    private var tokenCache: [String: CachedToken] = [:]
    private var pending: [String: [PendingRequest]] = [:]
    private var timeoutWorkItems: [String: DispatchWorkItem] = [:]
    private var activeAttemptIDs: [String: String] = [:]
    private var isLoaded = false
    private var loadCallbacks: [() -> Void] = []

    private lazy var webView: WKWebView = {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = contentController
        config.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isHidden = true
        webView.navigationDelegate = self
        contentController.add(self, name: "webPoToken")
        contentController.add(self, name: "webPoError")
        contentController.add(self, name: "webPoLog")
        contentController.add(self, name: "webPoGenerateIT")
        return webView
    }()

    private override init() {
        super.init()
        loadPersistedCache()
        DispatchQueue.main.async { [weak self] in
            self?.loadIfNeeded()
        }
    }

    func fetchSessionToken(identifier: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            if let cached = self.validCachedToken(for: identifier) {
                print("[WebPoTokenService] cache hit for content token")
                DispatchQueue.main.async {
                    completion(.success(cached.token))
                }
                return
            }

            let request = PendingRequest(identifier: identifier, retryCount: 0, completion: completion)
            self.pending[identifier, default: []].append(request)

            if self.pending[identifier]?.count ?? 0 > 1 {
                print("[WebPoTokenService] joined pending mint for visitorData")
                return
            }

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.resolve(identifier: identifier, result: .failure(ServiceError.timedOut("WebPO mint timed out after \(Int(self.mintTimeout))s")))
            }
            self.timeoutWorkItems[identifier] = timeoutWorkItem
            self.queue.asyncAfter(deadline: .now() + self.mintTimeout, execute: timeoutWorkItem)

            DispatchQueue.main.async {
                print("[WebPoTokenService] scheduling mint attempt=0")
                self.ensureReady {
                    self.runMint(identifier: identifier)
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded, webView.url == nil else { return }
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>YTVLite WebPO</title>
        </head>
        <body></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    private func ensureReady(_ completion: @escaping () -> Void) {
        if isLoaded {
            completion()
            return
        }
        loadCallbacks.append(completion)
        loadIfNeeded()
    }

    private func runMint(identifier: String) {
        guard let identifierLiteral = jsStringLiteral(identifier),
              let requestKeyLiteral = jsStringLiteral(requestKey)
        else {
            resolve(identifier: identifier, result: .failure(ServiceError.invalidMessage))
            return
        }
        let attemptID = UUID().uuidString
        guard let attemptLiteral = jsStringLiteral(attemptID) else {
            resolve(identifier: identifier, result: .failure(ServiceError.invalidMessage))
            return
        }
        queue.async {
            self.activeAttemptIDs[identifier] = attemptID
        }

        print("[WebPoTokenService] mint start")

        let script = """
        (() => {
          const identifier = \(identifierLiteral);
          const attemptID = \(attemptLiteral);
          const requestKey = \(requestKeyLiteral);
          const googApiKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw";
          const postLog = (message) => window.webkit.messageHandlers.webPoLog.postMessage({ identifier, attemptID, message });

          function getHeaders() {
            return {
              "content-type": "application/json+protobuf",
              "x-goog-api-key": googApiKey,
              "x-user-agent": "grpc-web-javascript/0.1"
            };
          }

          async function fetchWithTimeout(url, init, timeoutMs, label) {
            return await Promise.race([
              fetch(url, init),
              new Promise((_, reject) => setTimeout(() => reject(new Error(label + " timeout")), timeoutMs))
            ]);
          }

          function base64ToU8(base64) {
            const normalized = base64.replace(/[-_.]/g, (ch) => ({ "-": "+", "_": "/", ".": "=" }[ch]));
            const bin = atob(normalized);
            return new Uint8Array(Array.from(bin).map((char) => char.charCodeAt(0)));
          }

          function u8ToBase64(u8, base64url) {
            const result = btoa(String.fromCharCode(...u8));
            if (!base64url) return result;
            return result.replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=/g, "");
          }

          window.__ytvliteWebPoState = window.__ytvliteWebPoState || {};

          window.__ytvliteContinueMint = async (identifier, attemptID, integrityToken) => {
            try {
              const state = window.__ytvliteWebPoState[identifier];
              if (!state || state.attemptID !== attemptID || !(state.getMinter instanceof Function)) {
                throw new Error("Stored minter missing");
              }

              postLog("mint_callback:start");
              const mintCallback = await state.getMinter(base64ToU8(integrityToken));
              if (!(mintCallback instanceof Function)) {
                throw new Error("Mint callback invalid");
              }

              postLog("mint:start");
              const tokenBytes = await mintCallback(new TextEncoder().encode(identifier));
              if (!(tokenBytes instanceof Uint8Array)) {
                throw new Error("Mint result invalid");
              }

              postLog("mint:ok");
              window.webkit.messageHandlers.webPoToken.postMessage({
                identifier,
                attemptID,
                token: u8ToBase64(tokenBytes, true)
              });
            } catch (error) {
              const message = error && error.message ? error.message : String(error);
              window.webkit.messageHandlers.webPoError.postMessage({ identifier, attemptID, message });
            }
          };

          function descramble(scrambled) {
            const buffer = base64ToU8(scrambled);
            if (!buffer.length) return undefined;
            return new TextDecoder().decode(buffer.map((b) => b + 97));
          }

          async function createChallenge() {
            postLog("challenge:create:start");
            const response = await fetchWithTimeout("https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/Create", {
              method: "POST",
              headers: getHeaders(),
              body: JSON.stringify([ requestKey ])
            }, 8000, "Challenge");

            if (!response.ok) {
              throw new Error("Challenge failed with status " + response.status);
            }

            const rawData = await response.json();
            postLog("challenge:create:ok");
            let challengeData = [];

            if (rawData.length > 1 && typeof rawData[1] === "string") {
              challengeData = JSON.parse(descramble(rawData[1]) || "[]");
            } else if (rawData.length && typeof rawData[0] === "object") {
              challengeData = rawData[0];
            }

            const [ messageId, wrappedScript, wrappedUrl, interpreterHash, program, globalName ] = challengeData;
            const interpreterJavascript = Array.isArray(wrappedScript)
              ? wrappedScript.find((value) => value && typeof value === "string")
              : null;
            const interpreterUrl = Array.isArray(wrappedUrl)
              ? wrappedUrl.find((value) => value && typeof value === "string")
              : null;

            if (!interpreterJavascript || !program || !globalName) {
              throw new Error("Malformed challenge response");
            }

            postLog("challenge:parsed");
            postLog("challenge:meta:" + [messageId || "nil", interpreterHash || "nil", globalName || "nil", interpreterUrl || "nil"].join("|"));
            return { interpreterJavascript, interpreterHash, program, globalName };
          }

          async function generatePoToken() {
            const challenge = await createChallenge();
            postLog("vm:script:eval");
            const scriptId = challenge.interpreterHash || ("ytvlite-bg-" + identifier);
            if (!document.getElementById(scriptId)) {
              const script = document.createElement("script");
              script.type = "text/javascript";
              script.id = scriptId;
              script.textContent = challenge.interpreterJavascript;
              document.head.appendChild(script);
            }

            const vm = globalThis[challenge.globalName];
            if (!vm || !vm.a) {
              throw new Error("BotGuard VM not available");
            }
            postLog("vm:ready");

            let asyncSnapshotFunction;
            const vmFunctionsCallback = (asyncSnapshot, _shutdown, _passEvent, _checkCamera) => {
              asyncSnapshotFunction = asyncSnapshot;
            };

            const vmInitResult = await vm.a(challenge.program, vmFunctionsCallback, true, undefined, () => {}, [ [], [] ]);
            postLog("vm:loaded");
            postLog("vm:init:type:" + (Array.isArray(vmInitResult) ? "array" : typeof vmInitResult));
            if (Array.isArray(vmInitResult)) {
              postLog("vm:init:length:" + vmInitResult.length);
              postLog("vm:init:slot0:" + (vmInitResult[0] instanceof Function ? "function" : typeof vmInitResult[0]));
            }

            if (!asyncSnapshotFunction) {
              throw new Error("Async snapshot function not found");
            }

            const webPoSignalOutput = [];
            postLog("snapshot:start");
            const botguardResponse = await new Promise((resolve, reject) => {
              asyncSnapshotFunction((response) => resolve(response), [
                undefined,
                undefined,
                webPoSignalOutput,
                undefined
              ]);
              setTimeout(() => reject(new Error("BotGuard snapshot timeout")), 5000);
            });
            postLog("snapshot:ok");
            postLog("snapshot:signal:length:" + webPoSignalOutput.length);
            postLog("snapshot:signal:types:" + webPoSignalOutput.map((value) => {
              if (value instanceof Function) return "function";
              if (value === undefined) return "undefined";
              if (value === null) return "null";
              if (Array.isArray(value)) return "array";
              return typeof value;
            }).join(","));

            const getMinter = webPoSignalOutput[0];
            if (!(getMinter instanceof Function)) {
              throw new Error("Minter not found");
            }
            window.__ytvliteWebPoState[identifier] = { getMinter, attemptID };
            postLog("generate_it:start");
            window.webkit.messageHandlers.webPoGenerateIT.postMessage({ identifier, attemptID, botguardResponse });
          }

          (async () => {
            try {
              await generatePoToken();
            } catch (error) {
              const message = error && error.message ? error.message : String(error);
              window.webkit.messageHandlers.webPoError.postMessage({ identifier, attemptID, message });
            }
          })();
        })();
        true;
        """

        webView.evaluateJavaScript(script) { _, error in
            if let error {
                let isCurrentAttempt = self.queue.sync {
                    self.activeAttemptIDs[identifier] == attemptID
                }
                guard isCurrentAttempt else {
                    print("[WebPoTokenService] ignoring stale mint evaluation error: \(error.localizedDescription)")
                    return
                }
                self.resolve(identifier: identifier, result: .failure(error))
            }
        }
    }

    private func resolve(identifier: String, result: Result<String, Error>) {
        queue.async {
            let completions = self.pending.removeValue(forKey: identifier) ?? []
            let timeoutWorkItem = self.timeoutWorkItems.removeValue(forKey: identifier)
            timeoutWorkItem?.cancel()
            self.activeAttemptIDs.removeValue(forKey: identifier)
            guard !completions.isEmpty else { return }

            if case .failure(let error) = result,
               self.shouldRetryAfterFailure(error),
               let maxRetry = completions.map(\.retryCount).max(),
               maxRetry < self.maxRetryCount {
                print("[WebPoTokenService] retrying mint after timeout")
                self.resetWebViewState()
                let retried = completions.map {
                    PendingRequest(identifier: $0.identifier, retryCount: $0.retryCount + 1, completion: $0.completion)
                }
                self.pending[identifier] = retried

                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.resolve(identifier: identifier, result: .failure(ServiceError.timedOut("WebPO mint timed out after \(Int(self.mintTimeout))s")))
                }
                self.timeoutWorkItems[identifier] = timeoutWorkItem
                self.queue.asyncAfter(deadline: .now() + self.mintTimeout, execute: timeoutWorkItem)

                DispatchQueue.main.async {
                    print("[WebPoTokenService] scheduling mint attempt=\(maxRetry + 1)")
                    self.ensureReady {
                        self.runMint(identifier: identifier)
                    }
                }
                return
            }

            if case .success(let token) = result {
                print("[WebPoTokenService] mint success")
                self.storeCachedToken(token, for: identifier)
            } else if case .failure(let error) = result {
                if let cached = self.staleFallbackToken(for: identifier) {
                    print("[WebPoTokenService] using stale cached content token after failure")
                    DispatchQueue.main.async {
                        completions.forEach { $0.completion(.success(cached.token)) }
                    }
                    return
                }
                print("[WebPoTokenService] mint failed: \(error)")
            }

            DispatchQueue.main.async {
                completions.forEach { $0.completion(result) }
            }
        }
    }

    private func shouldRetryAfterFailure(_ error: Error) -> Bool {
        if case ServiceError.timedOut = error {
            return true
        }
        return false
    }

    private func validCachedToken(for identifier: String) -> CachedToken? {
        guard let cached = tokenCache[identifier] else { return nil }
        return Date().timeIntervalSince(cached.createdAt) <= tokenCacheLifetime ? cached : nil
    }

    private func staleFallbackToken(for identifier: String) -> CachedToken? {
        guard let cached = tokenCache[identifier] else { return nil }
        return Date().timeIntervalSince(cached.createdAt) <= staleFallbackLifetime ? cached : nil
    }

    private func storeCachedToken(_ token: String, for identifier: String) {
        tokenCache[identifier] = CachedToken(token: token, createdAt: Date())
        persistCache()
    }

    private func loadPersistedCache() {
        guard let raw = UserDefaults.standard.dictionary(forKey: tokenCacheDefaultsKey) as? [String: [String: Any]] else {
            return
        }

        var loaded: [String: CachedToken] = [:]
        for (identifier, entry) in raw {
            guard let token = entry["token"] as? String,
                  let timestamp = entry["createdAt"] as? TimeInterval
            else { continue }
            loaded[identifier] = CachedToken(token: token, createdAt: Date(timeIntervalSince1970: timestamp))
        }
        tokenCache = loaded
    }

    private func persistCache() {
        let serialized = tokenCache.mapValues { cached in
            [
                "token": cached.token,
                "createdAt": cached.createdAt.timeIntervalSince1970
            ]
        }
        UserDefaults.standard.set(serialized, forKey: tokenCacheDefaultsKey)
    }

    private func resetWebViewState() {
        DispatchQueue.main.async {
            self.webView.stopLoading()
            self.isLoaded = false
            self.loadCallbacks.removeAll()
            self.webView.loadHTMLString("""
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>YTVLite WebPO</title>
            </head>
            <body></body>
            </html>
            """, baseURL: URL(string: "https://www.youtube.com"))
        }
    }

    private func continueMint(identifier: String, attemptID: String?, integrityToken: String) {
        guard let identifierLiteral = jsStringLiteral(identifier),
              let tokenLiteral = jsStringLiteral(integrityToken)
        else {
            resolve(identifier: identifier, result: .failure(ServiceError.invalidMessage))
            return
        }
        let attemptArgument: String
        if let attemptID, let attemptLiteral = jsStringLiteral(attemptID) {
            attemptArgument = attemptLiteral
        } else {
            attemptArgument = "undefined"
        }

        let script = """
        (() => {
          if (window.__ytvliteContinueMint) {
            window.__ytvliteContinueMint(\(identifierLiteral), \(attemptArgument), \(tokenLiteral));
          } else {
            window.webkit.messageHandlers.webPoError.postMessage({
              identifier: \(identifierLiteral),
              attemptID: \(attemptArgument),
              message: "Continue mint function missing"
            });
          }
        })();
        true;
        """

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script) { _, error in
                if let error {
                    let isCurrentAttempt = self.queue.sync {
                        self.activeAttemptIDs[identifier] == attemptID
                    }
                    guard isCurrentAttempt else {
                        print("[WebPoTokenService] ignoring stale continueMint evaluation error: \(error.localizedDescription)")
                        return
                    }
                    self.resolve(identifier: identifier, result: .failure(error))
                }
            }
        }
    }

    private func startGenerateIT(identifier: String, attemptID: String?, botguardResponse: String) {
        print("[WebPoTokenService] generate_it:native:start")

        guard let url = URL(string: "https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/GenerateIT") else {
            resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed("Invalid URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json+protobuf", forHTTPHeaderField: "content-type")
        request.setValue("AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw", forHTTPHeaderField: "x-goog-api-key")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")

        guard let body = try? JSONSerialization.data(withJSONObject: [requestKey, botguardResponse], options: []) else {
            resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed("Invalid body")))
            return
        }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[WebPoTokenService] generate_it:native:error \(error.localizedDescription)")
                self.resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed(error.localizedDescription)))
                return
            }

            if let http = response as? HTTPURLResponse {
                print("[WebPoTokenService] generate_it:native:status \(http.statusCode)")
            }

            guard let data else {
                self.resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed("No data")))
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                let text = String(data: data, encoding: .utf8) ?? "<binary>"
                print("[WebPoTokenService] generate_it:native:raw \(text.prefix(300))")
                self.resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed("Invalid JSON")))
                return
            }

            let integrityToken = self.extractIntegrityToken(from: json)
            print("[WebPoTokenService] generate_it:native:shape \(String(describing: json).prefix(500))")

            guard let integrityToken, !integrityToken.isEmpty else {
                self.resolve(identifier: identifier, result: .failure(ServiceError.generateITFailed("Missing integrity token")))
                return
            }

            print("[WebPoTokenService] generate_it:native:ok")
            self.continueMint(identifier: identifier, attemptID: attemptID, integrityToken: integrityToken)
        }.resume()
    }

    private func extractIntegrityToken(from json: Any) -> String? {
        if let string = json as? String, !string.isEmpty {
            return string
        }
        if let array = json as? [Any] {
            for value in array {
                if let token = extractIntegrityToken(from: value) {
                    return token
                }
            }
        }
        if let dict = json as? [String: Any] {
            if let token = dict["integrityToken"] as? String, !token.isEmpty {
                return token
            }
            for value in dict.values {
                if let token = extractIntegrityToken(from: value) {
                    return token
                }
            }
        }
        return nil
    }

    private func jsStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2
        else {
            return nil
        }
        return String(json.dropFirst().dropLast())
    }
}

extension WebPoTokenService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

extension WebPoTokenService: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let identifier = body["identifier"] as? String
        else {
            return
        }
        let attemptID = body["attemptID"] as? String
        let isCurrentAttempt = queue.sync {
            guard let activeAttemptID = activeAttemptIDs[identifier] else {
                return false
            }
            guard let attemptID else {
                return false
            }
            return activeAttemptID == attemptID
        }
        if !isCurrentAttempt {
            if let text = body["message"] as? String {
                print("[WebPoTokenService] ignoring stale \(message.name): \(text)")
            } else {
                print("[WebPoTokenService] ignoring stale \(message.name)")
            }
            return
        }

        switch message.name {
        case "webPoToken":
            if let token = body["token"] as? String, !token.isEmpty {
                resolve(identifier: identifier, result: .success(token))
            } else {
                resolve(identifier: identifier, result: .failure(ServiceError.invalidMessage))
            }
        case "webPoError":
            let text = body["message"] as? String ?? "Unknown WebPO error"
            resolve(identifier: identifier, result: .failure(ServiceError.mintFailed(text)))
        case "webPoGenerateIT":
            if let botguardResponse = body["botguardResponse"] as? String, !botguardResponse.isEmpty {
                startGenerateIT(identifier: identifier, attemptID: attemptID, botguardResponse: botguardResponse)
            } else {
                resolve(identifier: identifier, result: .failure(ServiceError.invalidMessage))
            }
        case "webPoLog":
            if let text = body["message"] as? String {
                print("[WebPoTokenService] \(text)")
            }
        default:
            break
        }
    }
}
