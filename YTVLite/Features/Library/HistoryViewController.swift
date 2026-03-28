import UIKit

final class HistoryViewController: UIViewController {
    static let skeletonCount = 6
    private let service: HistoryService
    private let cache: AppCache
    let channelViewControllerFactory: (
        String,
        String
    ) -> ChannelViewController
    let videoRouter: VideoRouter
    var videos: [Video] = []
    var continuationToken: String?
    var isLoadingMore = false
    var isLoadingInitial = true
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()

    init(
        service: HistoryService,
        cache: AppCache = .shared,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.service = service
        self.cache = cache
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        setupTableView()
        setupSpinner()
        setupEmpty()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        if OAuthClient.shared.isSignedIn {
            loadFromCacheThenFetch()
        } else {
            spinner.stopAnimating()
            isLoadingInitial = false
            showSignInRequired()
        }
    }

    // MARK: - Setup

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
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refresh
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

    private func setupEmpty() {
        emptyLabel.textColor = .lightGray
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func showSignInRequired() {
        emptyLabel.text = "Sign in to view your watch history"
        emptyLabel.isHidden = false
    }

    // MARK: - Theme

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        if let rc = tableView.refreshControl {
            rc.tintColor = theme.secondaryText
        }
        tableView.reloadData()
    }

    // MARK: - Data

    /// Show cached data immediately, then silently refresh in background.
    private func loadFromCacheThenFetch() {
        cache.loadHistoryFeed { [weak self] cached in
            guard let self else {
                return
            }
            if let cached, !cached.videos.isEmpty {
                self.isLoadingInitial = false
                self.spinner.stopAnimating()
                self.videos = cached.videos
                self.continuationToken = cached.continuation
                self.tableView.reloadData()
                self.fetchHistory(showSpinner: false)
            } else {
                self.fetchHistory(showSpinner: true)
            }
        }
    }

    private func fetchHistory(showSpinner: Bool) {
        if showSpinner {
            isLoadingInitial = true
            spinner.startAnimating()
        }
        service.fetchHistory { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.tableView.refreshControl?.endRefreshing()
                self?.isLoadingInitial = false
                switch result {
                case .success(let page):
                    self?.applyHistoryPage(page)
                case .failure(let error):
                    self?.handleHistoryError(error)
                }
            }
        }
    }

    @objc
    private func handleRefresh() {
        cache.clearHistoryFeed()
        fetchHistory(showSpinner: false)
    }

    func loadMore() {
        guard let continuation = continuationToken, !isLoadingMore else {
            return
        }
        isLoadingMore = true
        OAuthClient.shared.validToken { [weak self] result in
            guard let self, case .success(let token) = result else {
                self?.isLoadingMore = false
                return
            }
            self.fetchNextPage(continuation: continuation, token: token)
        }
    }

    private func fetchNextPage(continuation: String, token: String) {
        service.fetchHistoryNextPage(
            continuation: continuation,
            token: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                if case .success(let page) = result {
                    self?.applyNextPage(page)
                }
            }
        }
    }
}

private extension HistoryViewController {
    func applyHistoryPage(_ page: FeedPage) {
        cache.setHistoryFeed(page)
        videos = page.videos
        continuationToken = page.continuation
        emptyLabel.isHidden = !page.videos.isEmpty
        if page.videos.isEmpty {
            emptyLabel.text = "No watch history found"
        }
        tableView.reloadData()
    }

    func handleHistoryError(_ error: Error) {
        AppLog.log("History", "error: \(error)")
        if videos.isEmpty {
            emptyLabel.text = "Could not load history"
            emptyLabel.isHidden = false
        }
        tableView.reloadData()
    }

    func applyNextPage(_ page: FeedPage) {
        let startIndex = videos.count
        videos.append(contentsOf: page.videos)
        continuationToken = page.continuation
        let indexPaths = (startIndex..<videos.count).map {
            IndexPath(row: $0, section: 0)
        }
        UIView.performWithoutAnimation {
            tableView.insertRows(at: indexPaths, with: .none)
        }
        let updated = FeedPage(
            videos: videos,
            continuation: continuationToken
        )
        cache.setHistoryFeed(updated)
    }
}
