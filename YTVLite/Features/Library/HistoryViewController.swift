import UIKit

final class HistoryViewController: UIViewController {

    private var videos: [Video] = []
    private var continuationToken: String?
    private var isLoadingMore = false
    private var isLoadingInitial = true
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()
    private static let skeletonCount = 6

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        setupTableView()
        setupSpinner()
        setupEmpty()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
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
        tableView.register(SubscriptionVideoCell.self,
                           forCellReuseIdentifier: SubscriptionVideoCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 220
        tableView.estimatedRowHeight = 220
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
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
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func showSignInRequired() {
        emptyLabel.text = "Sign in to view your watch history"
        emptyLabel.isHidden = false
    }

    // MARK: - Theme

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        if let rc = tableView.refreshControl {
            rc.tintColor = t.secondaryText
        }
        tableView.reloadData()
    }

    // MARK: - Data

    /// Show cached data immediately, then silently refresh in background.
    private func loadFromCacheThenFetch() {
        if let cached = AppCache.shared.cachedHistoryFeed(), !cached.videos.isEmpty {
            isLoadingInitial = false
            spinner.stopAnimating()
            videos = cached.videos
            continuationToken = cached.continuation
            tableView.reloadData()
            // Silently refresh in background
            fetchHistory(showSpinner: false)
        } else {
            fetchHistory(showSpinner: true)
        }
    }

    private func fetchHistory(showSpinner: Bool) {
        if showSpinner {
            isLoadingInitial = true
            spinner.startAnimating()
        }
        InnertubeClient.shared.fetchHistory { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                self.tableView.refreshControl?.endRefreshing()
                self.isLoadingInitial = false
                switch result {
                case .success(let page):
                    AppCache.shared.setHistoryFeed(page)
                    self.videos = page.videos
                    self.continuationToken = page.continuation
                    self.emptyLabel.isHidden = !page.videos.isEmpty
                    if page.videos.isEmpty {
                        self.emptyLabel.text = "No watch history found"
                    }
                    self.tableView.reloadData()
                case .failure(let error):
                    print("History error: \(error)")
                    if self.videos.isEmpty {
                        self.emptyLabel.text = "Could not load history"
                        self.emptyLabel.isHidden = false
                    }
                    self.tableView.reloadData()
                }
            }
        }
    }

    @objc private func handleRefresh() {
        AppCache.shared.clearHistoryFeed()
        fetchHistory(showSpinner: false)
    }

    private func loadMore() {
        guard let continuation = continuationToken, !isLoadingMore else { return }
        isLoadingMore = true
        OAuthClient.shared.validToken { [weak self] result in
            guard let self = self, case .success(let token) = result else {
                self?.isLoadingMore = false
                return
            }
            InnertubeClient.shared.fetchHistoryNextPage(continuation: continuation, token: token) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoadingMore = false
                    if case .success(let page) = result {
                        let startIndex = self.videos.count
                        self.videos.append(contentsOf: page.videos)
                        self.continuationToken = page.continuation
                        let indexPaths = (startIndex..<self.videos.count).map { IndexPath(row: $0, section: 0) }
                        UIView.performWithoutAnimation {
                            self.tableView.insertRows(at: indexPaths, with: .none)
                        }
                        let updated = FeedPage(videos: self.videos, continuation: self.continuationToken)
                        AppCache.shared.setHistoryFeed(updated)
                    }
                }
            }
        }
    }
}

// MARK: - DataSource / Delegate

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoadingInitial ? HistoryViewController.skeletonCount : videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionVideoCell.reuseId,
                                                 for: indexPath) as! SubscriptionVideoCell
        if isLoadingInitial {
            cell.configureSkeleton()
            return cell
        }
        let video = videos[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            guard let channelId = video.channelId else { return }
            self?.navigationController?.pushViewController(
                ChannelViewController(channelId: channelId, channelName: video.channelName),
                animated: true)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoadingInitial else { return }
        let video = videos[indexPath.row]
        VideoRouter.shared.open(video: video, from: self)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingInitial, !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 5
        else { return }
        loadMore()
    }
}
