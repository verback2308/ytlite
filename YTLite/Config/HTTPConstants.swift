// swiftlint:disable:this file_name
import Foundation

enum HTTPHeader {
    static let contentType        = "Content-Type"
    static let accept             = "Accept"
    static let acceptLanguage     = "Accept-Language"
    static let acceptEncoding     = "Accept-Encoding"
    static let authorization      = "Authorization"
    static let userAgent          = "User-Agent"
    static let origin             = "Origin"
    static let referer            = "Referer"
    static let range              = "Range"

    /// YouTube-specific headers
    static let xOrigin = "X-Origin"
    static let xYoutubeClientName    = "X-Youtube-Client-Name"
    static let xYoutubeClientVersion = "X-Youtube-Client-Version"
    static let xGoogVisitorId     = "X-Goog-Visitor-Id"
    static let xGoogApiKey        = "x-goog-api-key"
    static let xUserAgent         = "x-user-agent"
}

// MARK: - HTTP header value constants

enum HTTPHeaderValue {
    static let contentTypeJSON    = "application/json"
    static let contentTypeOctet   = "application/octet-stream"
    static let acceptLanguageEN   = "en-US,en;q=0.9"
}

// MARK: - User-Agent strings

enum UserAgent {
    /// Desktop Chrome 140 — used for WEB client Innertube requests.
    static let chromeDesktop = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "AppleWebKit/537.36 (KHTML, like Gecko)",
        "Chrome/140.0.0.0 Safari/537.36,gzip(gfe)"
    ].joined(separator: " ")

    /// Older Chrome — used for signed URL playback requests.
    static let chromeDesktopPlayback = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "AppleWebKit/537.36 (KHTML, like Gecko)",
        "Chrome/139.0.0.0 Safari/537.36"
    ].joined(separator: " ")

    /// Chrome on macOS — used for web-client direct playback.
    static let chromeMac = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/537.36 (KHTML, like Gecko)",
        "Chrome/122.0.0.0 Safari/537.36"
    ].joined(separator: " ")

    /// Cobalt (TV embedded browser) — used for TV/Onesie/OAuth requests.
    static let cobaltTV =
        "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version"

    /// Safari on macOS — used for WKWebView po_token generation.
    static let safariMac = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/18.0 Safari/605.1.15"
    ].joined(separator: " ")
}

// MARK: - YouTube API credentials

enum YouTubeCredentials {
    /// Public YouTube TV API key (embedded in TV client pages, not secret).
    static let tvApiKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"
}
