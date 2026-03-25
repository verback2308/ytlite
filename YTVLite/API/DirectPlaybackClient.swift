import Foundation

enum DirectPlaybackClient: Equatable, CustomStringConvertible {
    case tvHTML5
    case web
    case android
    case androidVR
    case ios

    var clientName: String {
        switch self {
        case .tvHTML5:
            return "TVHTML5"
        case .web:
            return "WEB"
        case .android:
            return "ANDROID"
        case .androidVR:
            return "ANDROID_VR"
        case .ios:
            return "IOS"
        }
    }

    var clientVersion: String {
        switch self {
        case .tvHTML5:
            return "7.20230405.08.01"
        case .web:
            return "2.20231121.08.00"
        case .android:
            return "19.09.37"
        case .androidVR:
            return "1.71.26"
        case .ios:
            return "19.45.4"
        }
    }

    var clientHeaderName: String {
        switch self {
        case .tvHTML5:
            return "7"
        case .web:
            return "1"
        case .android:
            return "3"
        case .androidVR:
            return "28"
        case .ios:
            return "5"
        }
    }

    /// Whether this client uses cookie-based auth (preflight) instead of OAuth
    var usesCookieAuth: Bool {
        switch self {
        case .androidVR, .ios:
            return true
        default:
            return false
        }
    }

    var description: String {
        clientName
    }
}
