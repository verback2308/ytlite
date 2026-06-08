import Foundation

enum ServiceContainer {
    // Single InnertubeClient instance shared across all service protocols.
    // Each property is typed to the narrowest protocol the caller needs — DIP in action.
    private static let client = InnertubeClient()

    static var feed: FeedService { client }
    static var history: HistoryService { client }
    static var search: SearchService { client }
    static var playlists: PlaylistService { client }
    static var channel: ChannelService { client }
    static var channelTabs: ChannelTabService { client }
    static var watch: WatchService { client }
    static var engagement: EngagementService { client }
    static var account: AccountService { client }

    /// Legacy accessor — prefer narrow protocols above for new code.
    static var video: VideoService { client }
}
