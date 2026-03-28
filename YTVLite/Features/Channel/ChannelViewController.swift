import UIKit

final class ChannelViewController: VideosViewController {
    private let client: ChannelService = ServiceContainer.channel
    private let feedClient: FeedService = ServiceContainer.feed
    private let engagementClient: EngagementService = ServiceContainer.engagement
    private let cache = AppCache.shared
    private let channelId: String
    private let initialChannelName: String
    private let headerView = ChannelHeaderView()
    private let errorLabel = UILabel()
    private var isSubscribed: Bool = false
    private var currentChannelPage: ChannelPage?

    private lazy var infoBarButton: UIBarButtonItem = {
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

    init(channelId: String, channelName: String) {
        self.channelId = channelId
        self.initialChannelName = channelName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialChannelName
        setupLayout()
        headerView.applyTheme(isSubscribed: isSubscribed)
        applyErrorLabelTheme()
        restoreFromCache()
        loadChannel()
    }

    override func applyTheme() {
        super.applyTheme()
        headerView.applyTheme(isSubscribed: isSubscribed)
        applyErrorLabelTheme()
    }

    override func handleRefresh() {
        cache.clearChannelPage(channelId: channelId)
        loadChannel()
    }

    override func handleLoadMore() {
        guard let ct = currentContinuation
        else {
            finishLoadingMore()
            return
        }
        feedClient.fetchNextPage(
            continuation: ct
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePageResult(result)
            }
        }
    }

    override func handleScroll(_ scrollView: UIScrollView) {
        headerView.updateForScroll(scrollView)
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
        case .failure(let error):
            AppLog.channel("load failed \(channelId): \(error)")
            finishLoadingMore()
            errorLabel.isHidden = false
        }
    }

    private func handlePageResult(
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

    private func updateInfoBarButton(for info: ChannelInfo) {
        let hasAbout = info.description != nil
            || info.contactInfo != nil
            || info.videoCountText != nil
        navigationItem.rightBarButtonItem = hasAbout
            ? infoBarButton : nil
    }
}

// MARK: - Data & Actions

extension ChannelViewController {
    private func applyChannelInfo(_ info: ChannelInfo) {
        headerView.update(with: info, fallback: initialChannelName)
        title = info.title.isEmpty ? initialChannelName : info.title
        updateInfoBarButton(for: info)
    }

    private func applyChannelPage(_ page: ChannelPage) {
        currentChannelPage = page
        headerView.update(
            with: page.info, fallback: initialChannelName
        )
        title = page.info.title.isEmpty
            ? initialChannelName : page.info.title
        applyPageSubscription(page)
        updateInfoBarButton(for: page.info)
        let enriched = page.withChannelAvatars()
        cache.setChannelPage(enriched, channelId: channelId)
        cache.setChannelInfo(page.info, channelId: channelId)
        setPage(enriched.videosPage)
        errorLabel.isHidden = !videos.isEmpty
        if let cv = collectionView {
            handleScroll(cv)
        }
    }

    private func applyPageSubscription(_ page: ChannelPage) {
        let txt = page.subscribeButtonText
            ?? (page.isSubscribed ? "Subscribed" : "Subscribe")
        headerView.updateSubscription(
            title: txt, isEnabled: !OAuthClient.shared.isAnonymous
        )
        isSubscribed = page.isSubscribed
        headerView.applyTheme(isSubscribed: isSubscribed)
    }

    @objc
    private func showAbout() {
        guard let page = currentChannelPage
        else {
            return
        }
        let vc = ChannelAboutViewController(page: page)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc
    private func subscribeButtonTapped() {
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        updateSubscribeUI(subscribed: isSubscribed, enabled: false)
        let handler = buildCompletion(wasSubscribed: wasSubscribed)
        if wasSubscribed {
            engagementClient.unsubscribeFromChannel(
                channelId: channelId, completion: handler
            )
        } else {
            engagementClient.subscribeToChannel(
                channelId: channelId, completion: handler
            )
        }
    }

    private func buildCompletion(
        wasSubscribed: Bool
    ) -> (Result<Void, Error>) -> Void {
        { [weak self] result in
            DispatchQueue.main.async {
                self?.handleSubscribeResult(
                    result, wasSubscribed: wasSubscribed
                )
            }
        }
    }

    private func handleSubscribeResult(
        _ result: Result<Void, Error>,
        wasSubscribed: Bool
    ) {
        updateSubscribeUI(subscribed: isSubscribed, enabled: true)
        switch result {
        case .success:
            let act = wasSubscribed ? "unsubscribed" : "subscribed"
            AppLog.subscribe("\(act) channelId=\(channelId)")
        case .failure(let error):
            let act = wasSubscribed ? "unsubscribe" : "subscribe"
            AppLog.subscribe(
                "\(act) failed channelId=\(channelId): \(error)"
            )
            isSubscribed = wasSubscribed
            updateSubscribeUI(
                subscribed: wasSubscribed, enabled: true
            )
        }
    }

    private func updateSubscribeUI(
        subscribed: Bool,
        enabled: Bool
    ) {
        let txt = subscribed ? "Subscribed" : "Subscribe"
        headerView.updateSubscription(
            title: txt, isEnabled: enabled
        )
        headerView.applyTheme(isSubscribed: subscribed)
    }
}
