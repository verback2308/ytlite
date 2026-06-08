import Foundation

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiryDate: Date
    var clientId: String
    var clientSecret: String
    var isExpired: Bool { expiryDate.timeIntervalSinceNow < 60 }
}

extension Notification.Name {
    static let authorizationRequired = Notification.Name(
        "authorizationRequired"
    )
    static let userDidSignOut = Notification.Name(
        "userDidSignOut"
    )
}
