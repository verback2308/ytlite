import Foundation

enum Config {
    static var accessToken: String { Secrets.accessToken }
    static let proxyBaseURL = "http://192.168.31.224:3939"

    // Switch to mock YouTube API server for UI development (run: node ../mock_server.mjs)
    static let useMock = true
    static let youtubeAPIBase = useMock
        ? "http://192.168.31.224:3941/youtube/v3"
        : "https://www.googleapis.com/youtube/v3"
}
