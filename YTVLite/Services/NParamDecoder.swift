import Foundation
import WebKit

/// Decodes the scrambled "n" parameter in YouTube video URLs by executing
/// YouTube's own player JavaScript (base.js) in a hidden WKWebView.
///
/// Without decoding, googlevideo.com returns 403 for direct video URLs.
final class NParamDecoder: NSObject {
    static let shared = NParamDecoder()

    private enum DecoderError: Error, CustomStringConvertible {
        case notReady
        case playerFetchFailed(String)
        case functionNotFound
        case decodeFailed(String)
        case timedOut

        var description: String {
            switch self {
            case .notReady: return "decoder not ready"
            case .playerFetchFailed(let msg): return "player fetch failed: \(msg)"
            case .functionNotFound: return "nsig function not found in player JS"
            case .decodeFailed(let msg): return "decode failed: \(msg)"
            case .timedOut: return "decode timed out"
            }
        }
    }

    private var webView: WKWebView?
    private var isReady = false
    private var isLoading = false
    private var pendingCallbacks: [(Result<Void, Error>) -> Void] = []
    private var nCache: [String: String] = [:]
    private let queue = DispatchQueue(label: "com.ytvlite.nparam-decoder")

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Transform a video URL by decoding its "n" parameter.
    /// If there is no "n" parameter, returns the original URL unchanged.
    func decodeURL(_ url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let nItem = items.first(where: { $0.name == "n" }),
              let nValue = nItem.value, !nValue.isEmpty
        else {
            // No n parameter — return as-is
            completion(.success(url))
            return
        }

        // Check cache
        queue.sync {
            if let cached = nCache[nValue] {
                print("[NParamDecoder] cache hit: \(nValue) -> \(cached)")
                var newItems = items.filter { $0.name != "n" }
                newItems.append(URLQueryItem(name: "n", value: cached))
                components.queryItems = newItems
                completion(.success(components.url ?? url))
                return
            }
        }

        ensureReady { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self?.executeNDecode(nValue: nValue, originalURL: url) { decodeResult in
                    switch decodeResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let decodedN):
                        self?.queue.sync {
                            self?.nCache[nValue] = decodedN
                        }
                        var newItems = items.filter { $0.name != "n" }
                        newItems.append(URLQueryItem(name: "n", value: decodedN))
                        components.queryItems = newItems
                        completion(.success(components.url ?? url))
                    }
                }
            }
        }
    }

    // MARK: - Setup

    /// Ensures the WKWebView is loaded with base.js and the decode function is ready.
    private func ensureReady(completion: @escaping (Result<Void, Error>) -> Void) {
        if isReady {
            completion(.success(()))
            return
        }

        queue.sync {
            pendingCallbacks.append(completion)
        }

        if isLoading { return }
        isLoading = true

        print("[NParamDecoder] starting setup...")
        fetchPlayerId { [weak self] result in
            switch result {
            case .failure(let error):
                self?.notifyPending(.failure(error))
            case .success(let playerId):
                self?.fetchBaseJS(playerId: playerId) { result2 in
                    switch result2 {
                    case .failure(let error):
                        self?.notifyPending(.failure(error))
                    case .success(let baseJS):
                        self?.setupWebView(baseJS: baseJS)
                    }
                }
            }
        }
    }

    private func fetchPlayerId(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/iframe_api") else {
            completion(.failure(DecoderError.playerFetchFailed("invalid URL")))
            return
        }
        print("[NParamDecoder] fetching player ID...")
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(DecoderError.playerFetchFailed(error.localizedDescription)))
                return
            }
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                completion(.failure(DecoderError.playerFetchFailed("empty response")))
                return
            }
            // Extract player ID from: player\/XXXXXXXX\/ or player/XXXXXXXX/
            let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
            guard let range = unescaped.range(of: "player/"),
                  let endRange = unescaped[range.upperBound...].range(of: "/")
            else {
                completion(.failure(DecoderError.playerFetchFailed("player ID not found in response")))
                return
            }
            let playerId = String(unescaped[range.upperBound..<endRange.lowerBound])
            print("[NParamDecoder] player ID: \(playerId)")
            completion(.success(playerId))
        }.resume()
    }

    private func fetchBaseJS(playerId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let urlStr = "https://www.youtube.com/s/player/\(playerId)/player_ias.vflset/en_US/base.js"
        guard let url = URL(string: urlStr) else {
            completion(.failure(DecoderError.playerFetchFailed("invalid base.js URL")))
            return
        }
        print("[NParamDecoder] fetching base.js (\(playerId))...")
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(DecoderError.playerFetchFailed(error.localizedDescription)))
                return
            }
            guard let data = data, let js = String(data: data, encoding: .utf8) else {
                completion(.failure(DecoderError.playerFetchFailed("empty base.js")))
                return
            }
            print("[NParamDecoder] base.js fetched: \(data.count) bytes")
            completion(.success(js))
        }.resume()
    }

    private func setupWebView(baseJS: String) {
        let funcName = findNSigFunctionName(in: baseJS)
        print("[NParamDecoder] nsig function name: \(funcName ?? "NOT FOUND")")

        guard let funcName = funcName else {
            notifyPending(.failure(DecoderError.functionNotFound))
            return
        }

        self.nsigFuncName = funcName

        // No patching needed — we call the URL class (g.qJ) directly,
        // which is already in global scope after <script> injection

        DispatchQueue.main.async { [weak self] in
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let wv = WKWebView(frame: .zero, configuration: config)
            self?.webView = wv

            let html = "<html><head></head><body></body></html>"
            wv.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))

            print("[NParamDecoder] loading blank page, will inject base.js via <script> element...")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let self = self else { return }
                // Inject base.js via <script> element (runs in page's global scope)
                self.injectViaScriptElement(wv: wv, js: baseJS, funcName: funcName)
            }
        }
    }

    private var nsigFuncName: String?
    private var urlClassName: String?

    private func injectViaScriptElement(wv: WKWebView, js: String, funcName: String) {
        // Store base.js in a blob and load it as a script element
        // Split into chunks to avoid JS string literal limits
        let chunkSize = 500_000
        let chunks = stride(from: 0, to: js.count, by: chunkSize).map { start -> String in
            let startIdx = js.index(js.startIndex, offsetBy: start)
            let endIdx = js.index(startIdx, offsetBy: min(chunkSize, js.count - start))
            return String(js[startIdx..<endIdx])
        }

        print("[NParamDecoder] injecting via script element (\(chunks.count) chunks)...")

        // First, set up the accumulator
        wv.evaluateJavaScript("window.__baseJS_chunks = []; true;") { _, _ in
            self.injectChunks(wv: wv, chunks: chunks, index: 0, funcName: funcName)
        }
    }

    private func injectChunks(wv: WKWebView, chunks: [String], index: Int, funcName: String) {
        if index >= chunks.count {
            // All chunks loaded, create script element
            let urlClass = self.urlClassName ?? "g.qJ"
            let createScript = """
            (function() {
                var s = document.createElement('script');
                s.textContent = window.__baseJS_chunks.join('');
                document.head.appendChild(s);
                delete window.__baseJS_chunks;
                return typeof \(urlClass);
            })();
            """
            wv.evaluateJavaScript(createScript) { [weak self] result, error in
                let typeStr = result as? String ?? "unknown"
                print("[NParamDecoder] after script injection: typeof \(urlClass) = \(typeStr), error: \(error?.localizedDescription ?? "none")")
                if typeStr == "function" {
                    self?.isReady = true
                    self?.isLoading = false
                    self?.notifyPending(.success(()))
                } else {
                    self?.isLoading = false
                    self?.notifyPending(.failure(DecoderError.functionNotFound))
                }
            }
            return
        }

        // Escape the chunk for JS string literal
        let chunk = chunks[index]
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let js = "window.__baseJS_chunks.push('\(chunk)'); true;"
        wv.evaluateJavaScript(js) { [weak self] _, error in
            if let error = error {
                print("[NParamDecoder] chunk \(index) injection error: \(error.localizedDescription)")
                self?.isLoading = false
                self?.notifyPending(.failure(DecoderError.decodeFailed("chunk injection failed")))
                return
            }
            self?.injectChunks(wv: wv, chunks: chunks, index: index + 1, funcName: funcName)
        }
    }

    // MARK: - Function name extraction

    /// Find the nsig transform function name using yt-dlp-style patterns.
    /// Looks for where the nsig function is CALLED: `.get("n"))&&(b=FUNC(a)`
    /// The nsig function takes a single n value string and returns the decoded value.
    /// Find the URL normalizer function name (e.g. RDD) that calls `new g.XX(url).get("n")`.
    /// We use RDD as an entry point — the actual n-param transform happens inside the URL class.
    private func findNSigFunctionName(in js: String) -> String? {
        // Pattern: FUNC=function(R){try{var w=(new URLCLASS(R,!0)).get("n")
        let pattern = "([a-zA-Z0-9_$]+)=function\\(([a-zA-Z])\\)\\{try\\{var [a-zA-Z]=\\(new ([a-zA-Z0-9_.]+)\\(\\2,!0\\)\\)\\.get\\(\"n\"\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let nameRange = Range(match.range(at: 1), in: js),
              let classRange = Range(match.range(at: 3), in: js)
        else {
            print("[NParamDecoder] could not find URL normalizer function")
            return nil
        }
        let funcName = String(js[nameRange])
        let className = String(js[classRange])
        print("[NParamDecoder] found \(funcName) using URL class \(className)")
        self.urlClassName = className
        return funcName
    }

    // MARK: - Decode execution

    private func executeNDecode(nValue: String, originalURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let webView = webView, let funcName = nsigFuncName else {
            completion(.failure(DecoderError.notReady))
            return
        }

        // Call the URL class directly: new UrlClass(url, true).get("n") returns decoded n
        let urlStr = originalURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        let urlClass = urlClassName ?? "g.qJ"

        let js = """
        (function() {
            var errors = [];
            var origUt = g.ut;
            g.ut = function(e) { errors.push(e && e.message || String(e)); };
            try {
                var obj = new \(urlClass)('\(urlStr)', true);
                var n = obj.get('n');
                g.ut = origUt;
                if (n) return 'N:' + n;
                return 'DIAG:get_n_null|errors=' + errors.join(';');
            } catch(e) {
                g.ut = origUt;
                return 'ERROR:' + e.name + ':' + e.message + '|errors=' + errors.join(';');
            }
        })()
        """

        print("[NParamDecoder] calling new \(urlClass)(url, true).get('n') for n=\(nValue)")

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("[NParamDecoder] JS error: \(error.localizedDescription)")
                    completion(.failure(DecoderError.decodeFailed(error.localizedDescription)))
                    return
                }

                let resultStr = result as? String ?? "nil(\(String(describing: result)))"
                print("[NParamDecoder] result: \(resultStr)")

                if resultStr.hasPrefix("N:") {
                    let decodedN = String(resultStr.dropFirst(2))
                    if decodedN == nValue {
                        print("[NParamDecoder] n unchanged — transform may not have worked")
                        completion(.failure(DecoderError.decodeFailed("n unchanged")))
                    } else {
                        print("[NParamDecoder] decoded: \(nValue) -> \(decodedN)")
                        completion(.success(decodedN))
                    }
                } else {
                    print("[NParamDecoder] failed: \(resultStr)")
                    completion(.failure(DecoderError.decodeFailed(resultStr)))
                }
            }
        }
    }

    // MARK: - Helpers

    private func notifyPending(_ result: Result<Void, Error>) {
        var callbacks: [(Result<Void, Error>) -> Void] = []
        queue.sync {
            callbacks = pendingCallbacks
            pendingCallbacks = []
        }
        for cb in callbacks {
            cb(result)
        }
    }
}
