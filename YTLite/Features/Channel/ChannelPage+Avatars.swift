import Foundation

extension ChannelPage {
    func withChannelAvatars() -> ChannelPage {
        let enriched = videosPage.videos.map { vid in
            Video(
                id: vid.id,
                title: vid.title,
                channelId: vid.channelId,
                channelName: vid.channelName,
                channelAvatarURL: vid.channelAvatarURL
                    ?? info.avatarURL,
                thumbnailURL: vid.thumbnailURL,
                viewCount: vid.viewCount,
                publishedAt: vid.publishedAt,
                duration: vid.duration,
                isLive: vid.isLive
            )
        }
        let feed = FeedPage(
            videos: enriched,
            continuation: videosPage.continuation
        )
        return ChannelPage(
            info: info,
            videosPage: feed,
            subscribeButtonText: subscribeButtonText,
            isSubscribed: isSubscribed
        )
    }
}
