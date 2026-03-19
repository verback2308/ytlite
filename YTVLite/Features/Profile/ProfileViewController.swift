import UIKit

class ProfileViewController: UIViewController {

    // Header
    private let avatarView = ThumbnailImageView(frame: .zero)
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let subscribersLabel = UILabel()

    // Theme section
    private let themeSegment = UISegmentedControl(items: ["Dark", "Light"])
    private let clearImageCacheButton = UIButton(type: .system)

    // Separator
    private let headerStack = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        setupUI()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        loadProfile()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Sign Out", style: .plain,
                                                            target: self, action: #selector(signOut))
    }

    @objc private func signOut() {
        OAuthClient.shared.signOut()
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let auth = AuthViewController()
        auth.onAuthorized = {
            appDelegate.window?.rootViewController = MainTabBarController()
        }
        appDelegate.window?.rootViewController = auth
    }

    private func setupUI() {
        // Avatar
        avatarView.layer.cornerRadius = 48
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        // Name
        nameLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Handle
        handleLabel.font = UIFont.systemFont(ofSize: 14)
        handleLabel.textAlignment = .center
        handleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subscribers
        subscribersLabel.font = UIFont.systemFont(ofSize: 14)
        subscribersLabel.textAlignment = .center
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false

        // Theme section title
        let themeTitle = UILabel()
        themeTitle.text = "Theme"
        themeTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        themeTitle.textColor = UIColor(white: 0.5, alpha: 1)
        themeTitle.translatesAutoresizingMaskIntoConstraints = false

        // Segment control
        themeSegment.selectedSegmentIndex = ThemeManager.shared.isDark ? 0 : 1
        themeSegment.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        themeSegment.translatesAutoresizingMaskIntoConstraints = false

        clearImageCacheButton.setTitle("Clear Image Cache", for: .normal)
        clearImageCacheButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        clearImageCacheButton.layer.cornerRadius = 10
        clearImageCacheButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        clearImageCacheButton.translatesAutoresizingMaskIntoConstraints = false
        clearImageCacheButton.addTarget(self, action: #selector(clearImageCacheTapped), for: .touchUpInside)

        // Separator line
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 0.3, alpha: 1)
        separator.translatesAutoresizingMaskIntoConstraints = false

        for v in [avatarView, nameLabel, handleLabel, subscribersLabel,
                  separator, themeTitle, themeSegment, clearImageCacheButton] {
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            avatarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),

            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            handleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            handleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subscribersLabel.topAnchor.constraint(equalTo: handleLabel.bottomAnchor, constant: 4),
            subscribersLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            separator.topAnchor.constraint(equalTo: subscribersLabel.bottomAnchor, constant: 32),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            themeTitle.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 24),
            themeTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            themeSegment.topAnchor.constraint(equalTo: themeTitle.bottomAnchor, constant: 12),
            themeSegment.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            themeSegment.widthAnchor.constraint(equalToConstant: 280),
            themeSegment.heightAnchor.constraint(equalToConstant: 32),

            clearImageCacheButton.topAnchor.constraint(equalTo: themeSegment.bottomAnchor, constant: 20),
            clearImageCacheButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        nameLabel.textColor = t.primaryText
        handleLabel.textColor = t.secondaryText
        subscribersLabel.textColor = t.secondaryText
        themeSegment.selectedSegmentIndex = t.isDark ? 0 : 1
        clearImageCacheButton.backgroundColor = t.isDark ? UIColor(white: 0.16, alpha: 1) : .white
        clearImageCacheButton.setTitleColor(t.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1), for: .normal)
    }

    @objc private func themeChanged() {
        ThemeManager.shared.isDark = themeSegment.selectedSegmentIndex == 0
    }

    @objc private func clearImageCacheTapped() {
        ThumbnailImageView.clearCache()

        let alert = UIAlertController(title: "Done", message: "Image cache cleared.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func loadProfile() {
        OAuthClient.shared.validToken { [weak self] result in
            guard case .success(let token) = result else { return }
            guard let url = URL(string: "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true") else { return }
            let headers = ["Authorization": "Bearer \(token)"]
            APIClient().get(url: url, headers: headers) { [weak self] result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = (json["items"] as? [[String: Any]])?.first,
                  let snippet = item["snippet"] as? [String: Any] else { return }

            let name = snippet["title"] as? String ?? ""
            let handle = snippet["customUrl"] as? String ?? ""
            let subs = (item["statistics"] as? [String: Any])?["subscriberCount"] as? String ?? ""
            let thumbs = snippet["thumbnails"] as? [String: Any] ?? [:]
            let thumb = (thumbs["high"] ?? thumbs["medium"] ?? thumbs["default"]) as? [String: Any]
            let thumbURL = thumb?["url"] as? String ?? ""

            DispatchQueue.main.async {
                self?.nameLabel.text = name
                self?.handleLabel.text = handle.isEmpty ? "" : "@\(handle.replacingOccurrences(of: "@", with: ""))"
                self?.subscribersLabel.text = subs.isEmpty ? "" : "\(subs) subscribers"
                if let url = URL(string: thumbURL) {
                    self?.avatarView.setImage(url: url)
                }
            }
        }
        }
    }
}
