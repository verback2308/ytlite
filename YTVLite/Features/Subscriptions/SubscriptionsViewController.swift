import UIKit

class SubscriptionsViewController: UIViewController {

    private let service = ServiceContainer.video
    private let cache = AppCache.shared
    private var videos: [Video] = []
    private var continuationToken: String?
    private var isLoadingMore = false
    private var seenVideoIds: Set<String> = []
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Subscriptions"
        setupTableView()
        setupSpinner()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)

        if let cachedPage = cache.cachedSubscriptionsFeed() {
            spinner.stopAnimating()
            setPage(cachedPage)
        } else {
            loadFeed()
        }
    }

    private func setupTableView() {
        tableView.register(SubscriptionVideoCell.self, forCellReuseIdentifier: SubscriptionVideoCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 220
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        tableView.reloadData()
    }

    @objc private func handleRefresh() {
        cache.clearSubscriptionsFeed()
        loadFeed()
    }

    private func loadFeed() {
        service.fetchSubscriptionFeed { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.tableView.refreshControl?.endRefreshing()
                switch result {
                case .success(let page):
                    self?.cache.setSubscriptionsFeed(page)
                    self?.setPage(page)
                case .failure(let error):
                    self?.finishLoadingMore()
                    print("Subscriptions error: \(error)")
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
                    print("Subscriptions pagination error: \(error)")
                }
            }
        }
    }

    private func setPage(_ page: FeedPage) {
        seenVideoIds = []
        videos = []
        appendPage(page)
    }

    private func appendPage(_ page: FeedPage) {
        let newVideos = page.videos.filter { seenVideoIds.insert($0.id).inserted }
        videos.append(contentsOf: newVideos)
        continuationToken = page.continuation
        isLoadingMore = false
        tableView.reloadData()
    }

    private func finishLoadingMore() {
        isLoadingMore = false
    }
}

extension SubscriptionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionVideoCell.reuseId, for: indexPath) as! SubscriptionVideoCell
        let video = videos[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            guard let channelId = video.channelId else { return }
            self?.navigationController?.pushViewController(ChannelViewController(channelId: channelId,
                                                                                channelName: video.channelName),
                                                           animated: true)
        }
        return cell
    }
}

extension SubscriptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let video = videos[indexPath.row]
        navigationController?.pushViewController(WatchViewController(video: video), animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 4
        else { return }

        isLoadingMore = true
        loadMore()
    }
}
