import Foundation

enum Config {
    static var accessToken: String { Secrets.accessToken }
    static let proxyBaseURL = "http://192.168.31.224:3939"
}
