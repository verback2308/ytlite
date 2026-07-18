import UIKit

class SubscriptionsViewController: UIViewController {
    static let skeletonCount = 6
    let service: FeedService
    let channelTabsService: ChannelTabService
    let channelsService: SubscribedChannelsService
    let cache: AppCache
    let channelViewControllerFactory: (
        String,
        String
    ) -> UIViewController
    let videoRouter: VideoRouter
    var videos: [Video] = []
    var continuationToken: String?
    var isLoadingMore = false
    var seenVideoIds: Set<String> = []
    var sortDatesByVideoId: [String: Date] = [:]
    let tableView = UITableView()
    let spinner = UIActivityIndicatorView(style: .white)
    let channelBar = ChannelAvatarBarView()
    var subscribedChannels: [SubscribedChannel] = []
    var selectedChannel: SubscribedChannel?
    var stashedVideos: [Video] = []
    var stashedContinuation: String?
    var stashedSeenVideoIds: Set<String> = []
    var isLoadingInitial = true
    var signInPrompt: SignInEmptyStateView?

    init(
        dependencies: AppDependencies,
        cache: AppCache = .shared,
        videoRouter: VideoRouter = .shared
    ) {
        service = dependencies.feedService
        channelTabsService = dependencies.channelTabService
        channelsService = dependencies.subscribedChannelsService
        channelViewControllerFactory = dependencies.makeChannelViewController
        self.cache = cache
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "订阅"
        AppLog.subs("viewDidLoad")
        setupTableView()
        setupSpinner()
        setupSignInPrompt()
        setupChannelBar()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowShortsChange),
            name: .showShortsSettingDidChange,
            object: nil
        )
        ToolbarManager.shared.install(in: self)
        observeTokenRefresh()
        loadInitialContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChannelBarFrame()
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        channelBar.applyTheme()
        tableView.reloadData()
    }

    @objc
    func handleRefresh() {
        if let channel = selectedChannel {
            loadChannelVideos(channel)
            return
        }
        cache.clearSubscriptionsFeed()
        cache.clearSubscribedChannels()
        loadFeed()
        loadSubscribedChannels(force: true)
    }

    @objc
    func handleShowShortsChange() {
        cache.clearSubscriptionsFeed()
        loadFeed()
    }
}

extension SubscriptionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoadingInitial ? SubscriptionsViewController.skeletonCount : videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionVideoCell.reuseId,
            for: indexPath
        ) as? SubscriptionVideoCell else {
            return UITableViewCell()
        }
        if isLoadingInitial {
            cell.configureSkeleton()
            return cell
        }
        let video = videos[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            guard let self else {
                return
            }
            guard let channelId = video.channelId else {
                return
            }
            self.navigationController?.pushViewController(
                self.channelViewControllerFactory(
                    channelId,
                    video.channelName
                ),
                animated: true
            )
        }
        return cell
    }
}

extension SubscriptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoadingInitial else {
            return
        }
        let video = videos[indexPath.row]
        videoRouter.open(video: video, from: self)
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard !isLoadingInitial,
              !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 4
        else { return }

        isLoadingMore = true
        loadMore()
    }
}
