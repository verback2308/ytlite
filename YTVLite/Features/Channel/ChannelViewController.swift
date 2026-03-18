import UIKit

final class ChannelViewController: VideosViewController {

    private let client = InnertubeClient()
    private let cache = AppCache.shared
    private let channelId: String
    private let initialChannelName: String

    private let headerView = UIView()
    private let avatarView = ThumbnailImageView(frame: .zero)
    private let nameLabel = UILabel()
    private let subscribersLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let separatorView = UIView()
    private let errorLabel = UILabel()

    override var columns: Int { 3 }

    init(channelId: String, channelName: String) {
        self.channelId = channelId
        self.initialChannelName = channelName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialChannelName
        setupHeader()
        applyHeaderTheme()

        if let cachedPage = cache.cachedChannelPage(channelId: channelId) {
            spinner.stopAnimating()
            applyChannelPage(cachedPage)
        } else {
            loadChannel()
        }
    }

    override func applyTheme() {
        super.applyTheme()
        applyHeaderTheme()
    }

    override func handleRefresh() {
        cache.clearChannelPage(channelId: channelId)
        loadChannel()
    }

    override func handleLoadMore() {
        guard let continuation = currentContinuation else {
            finishLoadingMore()
            return
        }

        client.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.appendPage(page)
                case .failure(let error):
                    print("[ChannelViewController] pagination failed \(self?.channelId ?? "nil"): \(error)")
                    self?.finishLoadingMore()
                }
            }
        }
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        avatarView.layer.cornerRadius = 32
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        subscribersLabel.font = UIFont.systemFont(ofSize: 14)
        subscribersLabel.textAlignment = .center
        subscribersLabel.numberOfLines = 2
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false

        subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        subscribeButton.isEnabled = false
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false

        separatorView.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.text = "Channel unavailable"
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.font = UIFont.systemFont(ofSize: 15)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true

        [avatarView, nameLabel, subscribersLabel, subscribeButton, separatorView, errorLabel].forEach {
            headerView.addSubview($0)
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.autoresizingMask = []

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            avatarView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            avatarView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),

            subscribersLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            subscribersLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            subscribersLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),

            subscribeButton.topAnchor.constraint(equalTo: subscribersLabel.bottomAnchor, constant: 14),
            subscribeButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            separatorView.topAnchor.constraint(equalTo: subscribeButton.bottomAnchor, constant: 18),
            separatorView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),
            separatorView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func applyHeaderTheme() {
        let theme = ThemeManager.shared
        headerView.backgroundColor = theme.background
        nameLabel.textColor = theme.primaryText
        subscribersLabel.textColor = theme.secondaryText
        separatorView.backgroundColor = theme.separator
        errorLabel.textColor = theme.secondaryText

        if subscribeButton.currentTitle == "Subscribed" {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(theme.primaryText, for: .normal)
        } else {
            subscribeButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    private func loadChannel() {
        errorLabel.isHidden = true
        client.fetchChannelPage(channelId: channelId) { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.endRefreshing()

                switch result {
                case .success(let page):
                    self?.applyChannelPage(page)
                case .failure(let error):
                    print("[ChannelViewController] load failed \(self?.channelId ?? "nil"): \(error)")
                    self?.finishLoadingMore()
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }

    private func applyChannelPage(_ page: ChannelPage) {
        title = page.info.title.isEmpty ? initialChannelName : page.info.title
        nameLabel.text = page.info.title.isEmpty ? initialChannelName : page.info.title
        subscribersLabel.text = page.info.subscriberCountText
        subscribeButton.setTitle(page.subscribeButtonText ?? (page.isSubscribed ? "Subscribed" : "Subscribe"), for: .normal)
        applyHeaderTheme()

        if let avatarURL = page.info.avatarURL, let url = URL(string: avatarURL) {
            avatarView.setImage(url: url)
        }

        let pageWithChannelAvatars = ChannelPage(info: page.info,
                                                 videosPage: FeedPage(videos: page.videosPage.videos.map {
            Video(id: $0.id,
                  title: $0.title,
                  channelId: $0.channelId,
                  channelName: $0.channelName,
                  channelAvatarURL: $0.channelAvatarURL ?? page.info.avatarURL,
                  thumbnailURL: $0.thumbnailURL,
                  viewCount: $0.viewCount,
                  publishedAt: $0.publishedAt,
                  duration: $0.duration)
        }, continuation: page.videosPage.continuation),
                                                 subscribeButtonText: page.subscribeButtonText,
                                                 isSubscribed: page.isSubscribed)

        cache.setChannelPage(pageWithChannelAvatars, channelId: channelId)
        setPage(pageWithChannelAvatars.videosPage)
        errorLabel.isHidden = !videos.isEmpty
    }
}
