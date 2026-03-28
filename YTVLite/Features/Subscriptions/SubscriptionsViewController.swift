import UIKit

class SubscriptionsViewController: UIViewController {
    private static let skeletonCount = 6
    private let service: FeedService = ServiceContainer.video
    private let cache = AppCache.shared
    private var videos: [Video] = []
    private var continuationToken: String?
    private var isLoadingMore = false
    private var seenVideoIds: Set<String> = []
    private var sortDatesByVideoId: [String: Date] = [:]
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private var isLoadingInitial = true
    private var signInPrompt: SignInEmptyStateView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Subscriptions"
        AppLog.subs("viewDidLoad")
        setupTableView()
        setupSpinner()
        setupSignInPrompt()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        ToolbarManager.shared.install(in: self)
        loadInitialContent()
    }

    private func loadInitialContent() {
        if OAuthClient.shared.isAnonymous {
            AppLog.subs("anonymous → skip load")
            spinner.stopAnimating()
            showSignInPrompt(true)
            return
        }
        cache.loadSubscriptionsFeed { [weak self] cachedPage in
            guard let self else {
                return
            }
            if let cachedPage {
                AppLog.subs("cache-hit → showing \(cachedPage.videos.count) videos instantly")
                self.isLoadingInitial = false
                self.spinner.stopAnimating()
                self.setPage(cachedPage)
            } else {
                AppLog.subs("no cache → loading from network")
                self.loadFeed()
            }
        }
    }

    private func setupSignInPrompt() {
        let prompt = SignInEmptyStateView(message: "Sign in to see your subscriptions")
        prompt.isHidden = true
        prompt.onSignIn = { [weak self] in self?.toolbarOpenProfile() }
        view.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            prompt.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            prompt.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            prompt.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        signInPrompt = prompt
    }
    private func showSignInPrompt(_ show: Bool) {
        signInPrompt?.isHidden = !show
        tableView.isHidden = show
    }

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 220
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }
    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }

    @objc
    private func handleRefresh() {
        cache.clearSubscriptionsFeed()
        loadFeed()
    }

    private func loadFeed() {
        let t0 = Date()
        AppLog.subs("network fetch start")
        service.fetchSubscriptionFeed { [weak self] result in
            DispatchQueue.main.async {
                let ms = Int(Date().timeIntervalSince(t0) * 1_000)
                self?.spinner.stopAnimating()
                self?.tableView.refreshControl?.endRefreshing()
                switch result {
                case .success(let page):
                    AppLog.subs("network fetch done \(ms)ms videos=\(page.videos.count)")
                    self?.showSignInPrompt(false)
                    self?.cache.setSubscriptionsFeed(page)
                    self?.setPage(page)
                case .failure(let error):
                    AppLog.subs("network fetch failed \(ms)ms: \(error)")
                    self?.finishLoadingMore()
                    if case APIError.unauthorized = error {
                        self?.isLoadingInitial = false
                        self?.showSignInPrompt(true)
                        self?.tableView.reloadData()
                    }
                }
            }
        }
    }
    private func loadMore() {
        guard let continuation = continuationToken else {
            finishLoadingMore()
            return
        }

        service.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.appendPage(page)
                case .failure(let error):
                    self?.finishLoadingMore()
                    AppLog.subs("pagination error: \(error)")
                }
            }
        }
    }
    private func setPage(_ page: FeedPage) {
        isLoadingInitial = false
        seenVideoIds = []
        sortDatesByVideoId = [:]
        videos = []
        appendPage(page)
    }
    private func appendPage(_ page: FeedPage) {
        let newVideos = page.videos.filter { seenVideoIds.insert($0.id).inserted }
        if !newVideos.isEmpty {
            let sortedNewVideos = newVideos.sorted {
                sortDate(for: $0) > sortDate(for: $1)
            }
            videos = mergeSortedVideos(videos, sortedNewVideos)
        }
        continuationToken = page.continuation
        isLoadingMore = false
        tableView.reloadData()
    }
    private func finishLoadingMore() {
        isLoadingMore = false
    }
}

private extension SubscriptionsViewController {
    func sortDate(for video: Video) -> Date {
        if let cached = sortDatesByVideoId[video.id] {
            return cached
        }
        let date = video.publishedAt.flatMap {
            VideoFormatters.approximateDate(fromRelative: $0)
        } ?? .distantPast
        sortDatesByVideoId[video.id] = date
        return date
    }

    func mergeSortedVideos(
        _ lhs: [Video],
        _ rhs: [Video]
    ) -> [Video] {
        guard !lhs.isEmpty else {
            return rhs
        }
        guard !rhs.isEmpty else {
            return lhs
        }

        var merged: [Video] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var lhsIndex = 0
        var rhsIndex = 0

        while lhsIndex < lhs.count, rhsIndex < rhs.count {
            let lhsVideo = lhs[lhsIndex]
            let rhsVideo = rhs[rhsIndex]
            if sortDate(for: lhsVideo) >= sortDate(for: rhsVideo) {
                merged.append(lhsVideo)
                lhsIndex += 1
            } else {
                merged.append(rhsVideo)
                rhsIndex += 1
            }
        }

        if lhsIndex < lhs.count {
            merged.append(contentsOf: lhs[lhsIndex...])
        }
        if rhsIndex < rhs.count {
            merged.append(contentsOf: rhs[rhsIndex...])
        }
        return merged
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
            guard let channelId = video.channelId else {
                return
            }
            self?.navigationController?.pushViewController(
                ChannelViewController(
                    channelId: channelId,
                    channelName: video.channelName
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
        VideoRouter.shared.open(video: video, from: self)
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
