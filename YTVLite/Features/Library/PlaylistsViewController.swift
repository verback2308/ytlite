import UIKit

final class PlaylistsViewController: UIViewController {
    private let service: PlaylistService
    private let channelViewControllerFactory: (
        String,
        String
    ) -> ChannelViewController
    private let videoRouter: VideoRouter
    private var playlists: [Playlist] = []
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()

    init(
        service: PlaylistService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.service = service
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playlists"
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
            loadPlaylists()
        } else {
            spinner.stopAnimating()
            showSignInRequired()
        }
    }

    private func setupTableView() {
        tableView.register(
            PlaylistCell.self,
            forCellReuseIdentifier: PlaylistCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 72
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            tableView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            tableView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
    }

    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            spinner.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            )
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
            emptyLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            emptyLabel.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            ),
            emptyLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 32
            ),
            emptyLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -32
            )
        ])
    }

    private func showSignInRequired() {
        tableView.isHidden = true
        emptyLabel.text = "Sign in to view your playlists"
        emptyLabel.isHidden = false
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }

    private func loadPlaylists() {
        service.fetchPlaylists { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                switch result {
                case .success(let list):
                    self?.playlists = list
                    self?.tableView.reloadData()
                    if list.isEmpty {
                        self?.emptyLabel.text = nil
                        self?.emptyLabel.isHidden = true
                    }
                case .failure:
                    self?.emptyLabel.text = "Could not load playlists"
                    self?.emptyLabel.isHidden = false
                }
            }
        }
    }
}

// MARK: - DataSource / Delegate

extension PlaylistsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        playlists.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PlaylistCell.reuseId,
            for: indexPath
        ) as? PlaylistCell else {
            return UITableViewCell()
        }
        cell.configure(with: playlists[indexPath.row])
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        let playlist = playlists[indexPath.row]
        let targetNav = navigationController?.parent?
            .navigationController ?? navigationController
        targetNav?.pushViewController(
            PlaylistVideosViewController(
                playlist: playlist,
                service: service,
                channelViewControllerFactory: channelViewControllerFactory,
                videoRouter: videoRouter
            ),
            animated: true
        )
    }
}
