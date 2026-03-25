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
    private var isLoadingInitial = true
    private static let skeletonCount = 6

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Subscriptions"
        setupTableView()
        setupSpinner()
        setupSignInPrompt()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        ToolbarManager.shared.install(in: self)

        if OAuthClient.shared.isAnonymous {
            spinner.stopAnimating()
            showSignInPrompt(true)
            return
        }

        if let cachedPage = cache.cachedSubscriptionsFeed() {
            isLoadingInitial = false
            spinner.stopAnimating()
            setPage(cachedPage)
        } else {
            loadFeed()
        }
    }

    private var signInPrompt: UIView?

    private func setupSignInPrompt() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13, *) {
            let iv = UIImageView(image: UIImage(systemName: "person.circle"))
            iv.tintColor = .lightGray
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: iconContainer.topAnchor),
                iv.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
                iv.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            ])
        }

        let label = UILabel()
        label.text = "Sign in to see your subscriptions"
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let signInBtn = UIButton(type: .system)
        signInBtn.setTitle("Sign In", for: .normal)
        signInBtn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        signInBtn.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        signInBtn.setTitleColor(.white, for: .normal)
        signInBtn.layer.cornerRadius = 10
        signInBtn.contentEdgeInsets = UIEdgeInsets(top: 12, left: 32, bottom: 12, right: 32)
        signInBtn.translatesAutoresizingMaskIntoConstraints = false
        signInBtn.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)

        [iconContainer, label, signInBtn].forEach { container.addSubview($0) }
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            iconContainer.topAnchor.constraint(equalTo: container.topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 64),
            iconContainer.heightAnchor.constraint(equalToConstant: 64),

            label.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            signInBtn.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            signInBtn.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            signInBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        signInPrompt = container
    }

    private func showSignInPrompt(_ show: Bool) {
        signInPrompt?.isHidden = !show
        tableView.isHidden = show
    }

    @objc private func signInTapped() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.showAuth()
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
                    self?.showSignInPrompt(false)
                    self?.cache.setSubscriptionsFeed(page)
                    self?.setPage(page)
                case .failure(let error):
                    self?.finishLoadingMore()
                    if case APIError.unauthorized = error {
                        self?.isLoadingInitial = false
                        self?.showSignInPrompt(true)
                        self?.tableView.reloadData()
                    }
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
        isLoadingInitial = false
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
        isLoadingInitial ? SubscriptionsViewController.skeletonCount : videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionVideoCell.reuseId, for: indexPath) as! SubscriptionVideoCell
        if isLoadingInitial {
            cell.configureSkeleton()
            return cell
        }
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
        guard !isLoadingInitial else { return }
        let video = videos[indexPath.row]
        VideoRouter.shared.open(video: video, from: self)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingInitial,
              !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 4
        else { return }

        isLoadingMore = true
        loadMore()
    }
}
