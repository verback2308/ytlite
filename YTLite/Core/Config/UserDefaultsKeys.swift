import Foundation

/// Centralised UserDefaults key namespace.
/// All keys used in the app must be declared here to prevent typos and collisions.
enum UserDefaultsKeys {
    enum Theme {
        static let mode = "themeMode"
        static let autoDarkStartHour = "theme_autoDarkStartHour"
        static let autoDarkEndHour = "theme_autoDarkEndHour"
    }

    enum VideoQuality {
        static let selected = "defaultVideoQuality"
    }

    enum Cache {
        static let feedPersistenceEnabled = "feedCachePersistenceEnabled"
        static let feedCacheDays = "feedCacheDays"
        static let imageCacheEnabled = "imageCacheEnabled"
        static let imageCacheDays = "imageCacheDays"
    }

    enum Auth {
        static let isAnonymous = "isAnonymous"
    }

    enum RYD {
        static let enabled    = "ryd_enabled"
        static let userId     = "ryd_userId_v2"
        static let registered = "ryd_registered_v2"
    }

    enum SponsorBlock {
        static let enabled = "sponsorblock_enabled"
        /// Returns the key for the skip-behavior setting of a given category raw value.
        static func segmentBehavior(for categoryRawValue: String) -> String {
            "sb_behavior_\(categoryRawValue)"
        }
    }

    enum Feed {
        static let showShorts = "feed_showShorts"
        static let homeLayout = "feed_homeLayout"
    }

    enum Search {
        static let history = "search_history"
    }

    enum Player {
        static let backgroundPlayback = "player_backgroundPlayback"
        static let pipEnabled = "player_pipEnabled"
        static let hideStatusBarInFullscreen = "player_hideStatusBarFullscreen"
        static let autoZoomToFill = "player_autoZoomToFill"
    }

    enum Innertube {
        static let visitorData = "innertube_visitorData"
        static let visitorDataDate = "innertube_visitorDataDate"
    }

    enum Debug {
        static let playbackSource = "debug_playbackSource"
        static let serverBaseURL = "debug_serverBaseURL"
    }

    enum Migration {
        static let playbackSourceAuto = "migration_playbackSourceAuto"
    }
}

// MARK: - PlaybackSource

enum PlaybackSource: String, CaseIterable {
    case auto = " auto"
    case androidVR = "android_vr"
    case progressive = "progressive"
    case mwebPot = "mweb_pot"

    static var selected: PlaybackSource {
        let raw = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Debug.playbackSource
        )
        return raw.flatMap(PlaybackSource.init)
            ?? .auto
    }

    var displayName: String {
        switch self {
        case .auto:
            return "自动(Android VR, mweb回退)"
        case .androidVR:
            return "Android VR (快速)"
        case .progressive:
            return "Progressive (360p)"
        case .mwebPot:
            return "移动网络+锅（儿童版/配音版）)"
        }
    }

    var sourceKind: VideoSourceKind {
        switch self {
        case .auto:
            return .auto
        case .androidVR:
            return .androidVR
        case .progressive:
            return .progressive
        case .mwebPot:
            return .mwebPot
        }
    }
}
