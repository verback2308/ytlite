import Foundation

struct AppDependencies {
    let feedService: FeedService
    let historyService: HistoryService
    let playlistService: PlaylistService
    let searchService: SearchService
    let channelService: ChannelService
    let watchService: WatchService
    let engagementService: EngagementService
    let accountService: AccountService

    static func live() -> AppDependencies {
        AppDependencies(
            feedService: ServiceContainer.feed,
            historyService: ServiceContainer.history,
            playlistService: ServiceContainer.playlists,
            searchService: ServiceContainer.search,
            channelService: ServiceContainer.channel,
            watchService: ServiceContainer.watch,
            engagementService: ServiceContainer.engagement,
            accountService: ServiceContainer.account
        )
    }

    func makeSearchViewController() -> SearchViewController {
        SearchViewController(
            service: searchService,
            channelViewControllerFactory: makeChannelViewController
        )
    }

    func makeWatchViewController(video: Video) -> WatchViewController {
        WatchViewController(
            video: video,
            watchService: watchService,
            engagementService: engagementService,
            channelInfoStore: .shared,
            channelViewControllerFactory: makeChannelViewController
        )
    }

    func makeChannelViewController(
        channelId: String,
        channelName: String
    ) -> ChannelViewController {
        ChannelViewController(
            channelId: channelId,
            channelName: channelName,
            channelService: channelService,
            feedService: feedService,
            engagementService: engagementService,
            channelViewControllerFactory: makeChannelViewController
        )
    }
}
