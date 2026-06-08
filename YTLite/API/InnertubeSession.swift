import Foundation

// MARK: - InnertubeSession
//
// Holds all immutable configuration for the Innertube API client.
// Mirrors the responsibility of YouTube.js Session — separating
// client config from request execution.
//
// InnertubeClient should depend on InnertubeSession for all config lookups,
// not store raw strings or inline context dictionaries.

final class InnertubeSession {
    // MARK: - Endpoints

    let baseURL: String = AppURLs.YouTube.innertube

    // MARK: - Client contexts

    var webContext: [String: Any] { InnertubeContexts.web }
    var tvContext: [String: Any] { InnertubeContexts.tv }
    var androidVRContext: [String: Any] { InnertubeContexts.androidVR }
    var androidContext: [String: Any] { InnertubeContexts.android }

    // MARK: - Mutable session state
    //
    // These are populated after session initialisation from the page or player response.
    // nil = not yet known (requests still work; YouTube returns defaults).

    /// Visitor data from the initial page response (`visitorData` field).
    var visitorData: String?

    /// Player signature timestamp — required for signed stream URLs.
    /// Extracted from the player JS or `/player` response.
    var signatureTimestamp: Int?

    // MARK: - URL helpers

    /// Builds a fully-qualified Innertube API URL for the given endpoint path.
    /// - Parameter endpoint: An `InnertubeEndpoint` path, e.g. `InnertubeEndpoint.browse`.
    func url(for endpoint: String) -> String {
        baseURL + endpoint
    }

    // MARK: - Context mutations
    //
    // Returns a copy of the given context with optional overrides applied.
    // Keeps base contexts immutable; callers never mutate the shared dicts.

    /// Returns a TV context, optionally appending a continuation token or browseId.
    func tvBrowseBody(
        browseId: String? = nil,
        continuation: String? = nil,
        params: String? = nil
    ) -> [String: Any] {
        var body = tvContext
        if let id = browseId { body[JSONKey.browseId] = id }
        if let cont = continuation { body[JSONKey.continuation] = cont }
        if let param = params { body[JSONKey.params] = param }
        return body
    }

    /// Returns a web context, optionally appending a continuation token or browseId.
    func webBrowseBody(
        browseId: String? = nil,
        continuation: String? = nil,
        params: String? = nil
    ) -> [String: Any] {
        var body = webContext
        if let id = browseId { body[JSONKey.browseId] = id }
        if let cont = continuation { body[JSONKey.continuation] = cont }
        if let param = params { body[JSONKey.params] = param }
        return body
    }
}
