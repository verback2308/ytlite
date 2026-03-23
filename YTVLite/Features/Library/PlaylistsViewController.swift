import UIKit

final class PlaylistsViewController: UIViewController {

    private let service = ServiceContainer.video
    private var playlists: [Playlist] = []
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playlists"
        setupTableView()
        setupSpinner()
        setupEmpty()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        if OAuthClient.shared.isSignedIn {
            loadPlaylists()
        } else {
            spinner.stopAnimating()
            showSignInRequired()
        }
    }

    private func setupTableView() {
        tableView.register(PlaylistCell.self, forCellReuseIdentifier: PlaylistCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 72
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
        tableView.isHidden = true
        emptyLabel.text = "Sign in to view your playlists"
        emptyLabel.isHidden = false
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        tableView.reloadData()
    }

    private func loadPlaylists() {
        service.fetchPlaylists { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                switch result {
                case .success(let list):
                    self?.playlists = list
                    if list.isEmpty {
                        self?.emptyLabel.text = "No playlists found"
                        self?.emptyLabel.isHidden = false
                    } else {
                        self?.tableView.reloadData()
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
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { playlists.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PlaylistCell.reuseId, for: indexPath) as! PlaylistCell
        cell.configure(with: playlists[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - PlaylistCell

final class PlaylistCell: UITableViewCell {
    static let reuseId = "PlaylistCell"

    private let thumb = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        thumb.layer.cornerRadius = 6
        thumb.layer.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = UIFont.systemFont(ofSize: 12)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumb)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumb.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 90),
            thumb.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: thumb.topAnchor),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        ])
        applyTheme()
    }

    @objc func applyTheme() {
        let t = ThemeManager.shared
        backgroundColor = t.background
        contentView.backgroundColor = t.background
        titleLabel.textColor = t.primaryText
        countLabel.textColor = t.secondaryText
    }

    func configure(with playlist: Playlist) {
        applyTheme()
        titleLabel.text = playlist.title
        if let count = playlist.itemCount {
            countLabel.text = "\(count) videos"
        } else {
            countLabel.text = nil
        }
        if let urlString = playlist.thumbnailURL, let url = URL(string: urlString) {
            thumb.setImage(url: url)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.cancel()
        titleLabel.text = nil
        countLabel.text = nil
    }
}
