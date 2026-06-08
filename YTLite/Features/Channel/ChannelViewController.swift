import UIKit

final class ChannelViewController: VideosViewController {
    let client: ChannelService
    let feedClient: FeedService
    let engagementClient: EngagementService
    let cache = AppCache.shared
    let channelId: String
    let initialChannelName: String
    let headerView = ChannelHeaderView()
    let tabsView = ChannelTabsView()
    let filterBar = ChannelFilterBarView()
    let errorLabel = UILabel()
    var isSubscribed: Bool = false
    var currentChannelPage: ChannelPage?
    var currentTab: ChannelTabsView.Tab = .videos
    var playlistLookup: [String: Playlist] = [:]

    lazy var infoBarButton: UIBarButtonItem = {
        if #available(iOS 13, *) {
            return UIBarButtonItem(
                image: UIImage(systemName: "info.circle"),
                style: .plain,
                target: self,
                action: #selector(showAbout)
            )
        }
        return UIBarButtonItem(
            title: "ℹ️",
            style: .plain,
            target: self,
            action: #selector(showAbout)
        )
    }()

    override var columns: Int {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 1
        }
        let width = view.bounds.width
        if width < 500 {
            return 1
        }
        return width > view.bounds.height ? 3 : 2
    }

    init(
        channelId: String,
        channelName: String,
        channelService: ChannelService,
        feedService: FeedService,
        engagementService: EngagementService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.channelId = channelId
        self.initialChannelName = channelName
        self.client = channelService
        self.feedClient = feedService
        self.engagementClient = engagementService
        super.init(
            channelViewControllerFactory: channelViewControllerFactory,
            videoRouter: videoRouter
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialChannelName
        setupLayout()
        headerView.applyTheme(isSubscribed: isSubscribed)
        tabsView.applyTheme()
        filterBar.applyTheme()
        applyErrorLabelTheme()
        restoreFromCache()
        loadChannel()
    }

    override func applyTheme() {
        super.applyTheme()
        headerView.applyTheme(isSubscribed: isSubscribed)
        tabsView.applyTheme()
        filterBar.applyTheme()
        applyErrorLabelTheme()
    }

    override func handleRefresh() {
        cache.clearChannelPage(channelId: channelId)
        loadChannel()
    }

    override func handleLoadMore() {
        guard let ct = currentContinuation else {
            finishLoadingMore()
            return
        }
        if currentTab == .playlists {
            loadMorePlaylists(continuation: ct)
        } else {
            loadMoreVideos(continuation: ct)
        }
    }

    override func handleScroll(_ scrollView: UIScrollView) {
        headerView.updateForScroll(scrollView)
        updateScrollInsets(for: scrollView)
    }

    private func setupLayout() {
        configureErrorLabel()
        guard let cv = collectionView else {
            return
        }
        headerView.install(
            in: view,
            collectionView: cv,
            errorLabel: errorLabel
        )
        installTabsView()
        headerView.subscribeButton.addTarget(
            self,
            action: #selector(subscribeButtonTapped),
            for: .touchUpInside
        )
    }

    private func configureErrorLabel() {
        errorLabel.text = "Channel unavailable"
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
    }

    private func applyErrorLabelTheme() {
        errorLabel.textColor = ThemeManager.shared.secondaryText
    }

    private func restoreFromCache() {
        let cid = channelId
        if let info = cache.cachedChannelInfo(channelId: cid) {
            applyChannelInfo(info)
        }
        if let page = cache.cachedChannelPage(channelId: cid) {
            spinner.stopAnimating()
            applyChannelPage(page)
        }
    }

    private func loadChannel() {
        errorLabel.isHidden = true
        client.fetchChannelPage(
            channelId: channelId
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleChannelResult(result)
            }
        }
    }

    private func handleChannelResult(
        _ result: Result<ChannelPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            applyChannelPage(page)
            loadCurrentTab()
        case .failure(let error):
            AppLog.channel("load failed \(channelId): \(error)")
            finishLoadingMore()
            errorLabel.isHidden = !videos.isEmpty
        }
    }

    func handlePageResult(
        _ result: Result<FeedPage, Error>
    ) {
        switch result {
        case .success(let page):
            appendPage(page)
        case .failure(let error):
            AppLog.channel(
                "pagination failed \(channelId): \(error)"
            )
            finishLoadingMore()
        }
    }

    override func openVideo(_ video: Video) {
        guard currentTab == .playlists,
              let playlist = playlistLookup[video.id] else {
            super.openVideo(video)
            return
        }
        openPlaylist(playlist)
    }
}
