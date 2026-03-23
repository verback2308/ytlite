import UIKit

final class HistoryViewController: UIViewController {

    private let service = ServiceContainer.video
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
            loadHistory()
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
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false
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
        tableView.reloadData()
    }

    // MARK: - Data

    private func loadHistory() {
        service.fetchHistory { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.isLoadingInitial = false
                switch result {
                case .success(let page):
                    self?.videos = page.videos
                    self?.continuationToken = page.continuation
                    if page.videos.isEmpty {
                        self?.emptyLabel.text = "No watch history found"
                        self?.emptyLabel.isHidden = false
                    }
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("History error: \(error)")
                    self?.emptyLabel.text = "Could not load history"
                    self?.emptyLabel.isHidden = false
                    self?.tableView.reloadData()
                }
            }
        }
    }

    private func loadMore() {
        guard let continuation = continuationToken else { return }
        isLoadingMore = true
        service.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                if case .success(let page) = result {
                    self?.videos.append(contentsOf: page.videos)
                    self?.continuationToken = page.continuation
                    self?.tableView.reloadData()
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
        navigationController?.pushViewController(WatchViewController(video: video), animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingInitial, !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 4
        else { return }
        isLoadingMore = true
        loadMore()
    }
}
