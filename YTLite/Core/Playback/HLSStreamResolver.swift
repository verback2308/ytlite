import Foundation
import JavaScriptCore

// MARK: - HLS Stream Resolver
//
// n-throttling signature solver + small HTTP/regex helpers used by the mweb
// playback source. `solveN` (see the +Solve / +Remote extensions) runs the
// EJS solver in an on-device JSContext (iOS 14+) or falls back to the remote
// solver (iOS 12/13, whose engine can't parse YouTube's ES2020 base.js).
// `fetchText` / `firstMatch` are used to scrape the player-JS URL from the
// watch page.

final class HLSStreamResolver {
    enum ResolverError: Error {
        case badResponse
    }

    static let shared = HLSStreamResolver()

    let desktopSafariUA = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.5 Safari/605.1.15"
    ].joined(separator: " ")

    let transport: HTTPTransport

    // Memoized solve results and player JS — solving is expensive (base.js
    // download + JS run on-device, or a round-trip to the remote solver),
    // while n values and the player script repeat across videos.
    private var solvedNCache: [String: String] = [:]
    private var playerJSCache: (path: String, text: String)?
    private let cacheLock = NSLock()

    // A single reused JS engine for on-device n-solving. Creating a fresh
    // JSContext (hence a fresh JSVirtualMachine) per solve leaks memory —
    // JavaScriptCore doesn't return a retired VM's memory to the OS — so the
    // solver library is loaded once and the context is reused. Serial access
    // only, via `solverQueue`; never touch `solverContext` off that queue.
    let solverQueue = DispatchQueue(label: "com.ytvlite.nsolve")
    var solverContext: JSContext?

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[group])
    }

    func fetchText(
        url: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let headers = [
            HTTPHeader.userAgent: desktopSafariUA,
            "Cookie": "SOCS=CAI",
            HTTPHeader.acceptLanguage: "en-US,en;q=0.9"
        ]
        transport.send(
            HTTPRequest(method: .get, url: url, headers: headers),
            cancellationToken: nil
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let response):
                if let text = String(data: response.data, encoding: .utf8) {
                    completion(.success(text))
                } else {
                    completion(.failure(ResolverError.badResponse))
                }
            }
        }
    }
}

// MARK: - Solver caches (used by the Solve/Remote extensions)

extension HLSStreamResolver {
    func cachedSolvedN(for key: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return solvedNCache[key]
    }

    func storeSolvedN(_ solved: String, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        solvedNCache[key] = solved
    }

    func cachedPlayerJS(path: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return playerJSCache?.path == path ? playerJSCache?.text : nil
    }

    func storePlayerJS(_ text: String, path: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        playerJSCache = (path, text)
    }
}
