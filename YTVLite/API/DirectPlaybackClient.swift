import Foundation

enum DirectPlaybackClient: Equatable, CustomStringConvertible {
    case androidVR
    case web

    var clientName: String {
        switch self {
        case .androidVR: return "ANDROID_VR"
        case .web:       return "WEB"
        }
    }

    var clientVersion: String {
        switch self {
        case .androidVR: return "1.71.26"
        case .web:       return "2.20231121.08.00"
        }
    }

    var clientHeaderName: String {
        switch self {
        case .androidVR: return "28"
        case .web:       return "1"
        }
    }

    var userAgent: String {
        switch self {
        case .androidVR:
            return "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
        case .web:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        }
    }

    /// Whether this client uses cookie-based auth (preflight) instead of OAuth Bearer token
    var usesCookieAuth: Bool {
        switch self {
        case .androidVR: return true
        case .web:       return false
        }
    }

    /// Whether the /player body needs contentCheckOk / racyCheckOk / playbackContext flags
    var requiresContentCheckFlags: Bool {
        return true
    }

    var context: [String: Any] {
        switch self {
        case .androidVR: return InnertubeContexts.androidVR
        case .web:       return InnertubeContexts.web
        }
    }

    var playerURLSuffix: String {
        switch self {
        case .androidVR: return "?prettyPrint=false"
        case .web:       return ""
        }
    }

    /// Build HTTP headers for stream requests (AVPlayer asset loading, direct URL fetches)
    func streamHeaders(visitorData: String?) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "*/*",
            "Accept-Language": "*",
            "User-Agent": userAgent,
            "X-Youtube-Client-Name": clientHeaderName,
            "X-Youtube-Client-Version": clientVersion
        ]
        switch self {
        case .web:
            headers["Referer"] = "https://www.youtube.com/"
            headers["Origin"] = "https://www.youtube.com"
            headers["X-Origin"] = "https://www.youtube.com"
        case .androidVR:
            break
        }
        if let visitorData, !visitorData.isEmpty {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        return headers
    }

    /// Build HTTP headers for /player API requests
    func apiHeaders(token: String, visitorData: String?) -> [String: String] {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if !usesCookieAuth {
            headers["Authorization"] = "Bearer \(token)"
        }
        headers["X-Youtube-Client-Name"] = clientHeaderName
        headers["X-Youtube-Client-Version"] = clientVersion
        headers["User-Agent"] = userAgent
        switch self {
        case .web:
            break
        case .androidVR:
            headers["Origin"] = "https://www.youtube.com"
            if let visitorData, !visitorData.isEmpty {
                headers["X-Goog-Visitor-Id"] = visitorData
            }
        }
        return headers
    }

    var description: String { clientName }
}
