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
    private let themeTitleLabel = UILabel()
    private let separatorLine = UIView()

    // Separator
    private let headerStack = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        setupUI()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        loadProfile()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Sign Out",
            style: .plain,
            target: self,
            action: #selector(signOut)
        )
    }

    @objc
    private func signOut() {
        OAuthClient.shared.signOut()
        UserProfileStore.shared.clear()
        AppCache.shared.clearHomeFeed()
        NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
    }

    private func setupUI() {
        setupHeaderViews()
        setupControlViews()
        setupConstraints()
    }

    private func setupHeaderViews() {
        avatarView.layer.cornerRadius = 48
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(avatarView)

        nameLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        handleLabel.font = UIFont.systemFont(ofSize: 14)
        handleLabel.textAlignment = .center
        handleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(handleLabel)

        subscribersLabel.font = UIFont.systemFont(ofSize: 14)
        subscribersLabel.textAlignment = .center
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subscribersLabel)
    }

    private func setupControlViews() {
        themeTitleLabel.text = "Theme"
        themeTitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        themeTitleLabel.textColor = UIColor(white: 0.5, alpha: 1)
        themeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(themeTitleLabel)

        themeSegment.selectedSegmentIndex = ThemeManager.shared.isDark ? 0 : 1
        themeSegment.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        themeSegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(themeSegment)

        clearImageCacheButton.setTitle("Clear Image Cache", for: .normal)
        clearImageCacheButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        clearImageCacheButton.layer.cornerRadius = 10
        let cacheInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        clearImageCacheButton.contentEdgeInsets = cacheInsets
        clearImageCacheButton.translatesAutoresizingMaskIntoConstraints = false
        clearImageCacheButton.addTarget(
            self,
            action: #selector(clearImageCacheTapped),
            for: .touchUpInside
        )
        view.addSubview(clearImageCacheButton)

        separatorLine.backgroundColor = UIColor(white: 0.3, alpha: 1)
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separatorLine)
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide
        let sepLine = separatorLine
        let cacheBtn = clearImageCacheButton
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: safe.topAnchor, constant: 32),
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
            sepLine.topAnchor.constraint(equalTo: subscribersLabel.bottomAnchor, constant: 32),
            sepLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sepLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sepLine.heightAnchor.constraint(equalToConstant: 1),
            themeTitleLabel.topAnchor.constraint(equalTo: sepLine.bottomAnchor, constant: 24),
            themeTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            themeSegment.topAnchor.constraint(equalTo: themeTitleLabel.bottomAnchor, constant: 12),
            themeSegment.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            themeSegment.widthAnchor.constraint(equalToConstant: 280),
            themeSegment.heightAnchor.constraint(equalToConstant: 32),
            cacheBtn.topAnchor.constraint(equalTo: themeSegment.bottomAnchor, constant: 20),
            cacheBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        nameLabel.textColor = theme.primaryText
        handleLabel.textColor = theme.secondaryText
        subscribersLabel.textColor = theme.secondaryText
        themeSegment.selectedSegmentIndex = theme.isDark ? 0 : 1
        let darkBg = UIColor(white: 0.16, alpha: 1)
        clearImageCacheButton.backgroundColor = theme.isDark ? darkBg : .white
        clearImageCacheButton.setTitleColor(theme.isDark ? .white : theme.accent, for: .normal)
    }

    @objc
    private func themeChanged() {
        ThemeManager.shared.isDark = themeSegment.selectedSegmentIndex == 0
    }

    @objc
    private func clearImageCacheTapped() {
        ThumbnailImageView.clearCache()

        let alert = UIAlertController(
            title: "Done",
            message: "Image cache cleared.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func loadProfile() {
        OAuthClient.shared.validToken { [weak self] result in
            guard case .success(let token) = result else {
                return
            }
            guard let url = URL(string: "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true") else {
                return
            }
            let headers = [HTTPHeader.authorization: "Bearer \(token)"]
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
                let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
                self?.handleLabel.text = handle.isEmpty ? "" : "@\(cleanHandle)"
                self?.subscribersLabel.text = subs.isEmpty ? "" : "\(subs) subscribers"
                if let url = URL(string: thumbURL) {
                    self?.avatarView.setImage(url: url)
                }
            }
            }
        }
    }
}
