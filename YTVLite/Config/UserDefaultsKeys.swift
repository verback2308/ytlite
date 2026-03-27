/// Centralised UserDefaults key namespace.
/// All keys used in the app must be declared here to prevent typos and collisions.
enum UserDefaultsKeys {

    enum Theme {
        static let mode = "themeMode"
    }

    enum VideoQuality {
        static let selected = "defaultVideoQuality"
    }

    enum Cache {
        static let feedPersistenceEnabled = "feedCachePersistenceEnabled"
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

    enum Player {
        static let backgroundPlayback = "player_backgroundPlayback"
    }
}
