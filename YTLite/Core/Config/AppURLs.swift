import Foundation

/// Centralised API base-URL namespace.
/// Actual endpoint paths are built locally in each service, but base URLs live here.
enum AppURLs {
    enum YouTube {
        static let base      = "https://www.youtube.com"
        static let innertube = "https://www.youtube.com/youtubei/v1"
        static let tv        = "https://www.youtube.com/tv"

        /// hqdefault thumbnail URL for a given video ID.
        static func thumbnailURL(videoId: String) -> String {
            "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        }
    }

    enum YouTubeOAuth {
        static let deviceCode = "https://www.youtube.com/o/oauth2/device/code"
        static let token      = "https://www.youtube.com/o/oauth2/token"
    }

    /// The deployed `solver-server` (n-solve + GVS pot mint). Only the base URL
    /// (host) is configured; the app derives `/solve` and `/get_pot` from it.
    /// Runtime override: `Debug.serverBaseURL` (empty = the built-in default).
    enum SolverServer {
        static let defaultBaseURL =
            "https://ytlite-solver.wonderfulpond-77505dfd.westus2.azurecontainerapps.io"

        /// The effective base URL — the runtime override if set, else the
        /// default — with any trailing slash trimmed.
        static var baseURL: String {
            let override = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Debug.serverBaseURL
            )
            let value = (override?.isEmpty == false) ? (override ?? "") : defaultBaseURL
            return value.hasSuffix("/") ? String(value.dropLast()) : value
        }

        static func endpoint(path: String) -> URL? {
            baseURL.isEmpty ? nil : URL(string: baseURL + path)
        }
    }

    /// Remote n-throttling solver (`/solve`). Only the mweb+pot source uses it.
    enum NSolver {
        static var endpoint: URL? { SolverServer.endpoint(path: "/solve") }
    }

    enum GoogleAPIs {
        static let youtubeV3 = "https://www.googleapis.com/youtube/v3"
    }

    /// Remote GVS proof-of-origin (`pot`) provider — the `solver-server`'s
    /// `/get_pot` endpoint (BotGuard minting can't be done reliably on-device).
    /// `POST /get_pot {"content_binding": <videoId>}`.
    enum PoTokenProvider {
        static var endpoint: URL? { SolverServer.endpoint(path: "/get_pot") }
    }

    enum RYD {
        static let api = "https://returnyoutubedislikeapi.com"
        static let web = "https://returnyoutubedislike.com"
    }

    enum SponsorBlock {
        static let api = "https://sponsor.ajay.app"
    }
}
