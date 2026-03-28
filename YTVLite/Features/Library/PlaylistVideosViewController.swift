import UIKit

final class PlaylistVideosViewController: UIViewController {
    private static let skeletonCount = 6

    private let playlist: Playlist
    private let service: PlaylistService
    private let channelViewControllerFactory: (
        String,
        String
    ) -> ChannelViewController
    private let videoRouter: VideoRouter
    private var videos: [Video] = []
    private var isLoading = true
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()

    init(
        playlist: Playlist,
        service: PlaylistService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.playlist = playlist
        self.service = service
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
        title = playlist.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        loadVideos()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
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

    private func loadVideos() {
        isLoading = true
        service.fetchPlaylistVideos(playlistId: playlist.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isLoading = false
                self.spinner.stopAnimating()
                self.tableView.refreshControl?.endRefreshing()
                switch result {
                case .success(let list):
                    self.videos = list
                    self.emptyLabel.isHidden = !list.isEmpty
                    if list.isEmpty {
                        self.emptyLabel.text = "No videos in this playlist"
                    }
                    self.tableView.reloadData()
                case .failure(let error):
                    AppLog.log("Playlist", "load error: \(error)")
                    self.emptyLabel.text = "Could not load playlist"
                    self.emptyLabel.isHidden = false
                    self.tableView.reloadData()
                }
            }
        }
    }

    @objc
    private func handleRefresh() {
        loadVideos()
    }
}

// MARK: - DataSource / Delegate

extension PlaylistVideosViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoading ? PlaylistVideosViewController.skeletonCount : videos.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionVideoCell.reuseId,
            for: indexPath
        ) as? SubscriptionVideoCell else {
            return UITableViewCell()
        }
        if isLoading {
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
            let parentNav = self.navigationController?.parent?.navigationController
            let targetNav = parentNav ?? self.navigationController
            targetNav?.pushViewController(
                self.channelViewControllerFactory(
                    channelId,
                    video.channelName
                ),
                animated: true
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoading else {
            return
        }
        let video = videos[indexPath.row]
        videoRouter.open(video: video, from: self)
    }
}
