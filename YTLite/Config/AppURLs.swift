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

    enum GoogleAPIs {
        static let youtubeV3 = "https://www.googleapis.com/youtube/v3"
    }

    enum RYD {
        static let api = "https://returnyoutubedislikeapi.com"
        static let web = "https://returnyoutubedislike.com"
    }

    enum SponsorBlock {
        static let api = "https://sponsor.ajay.app"
    }
}
