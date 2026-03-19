import UIKit
import AVKit

final class WatchViewController: UIViewController {

    private let initialVideo: Video
    private let client = InnertubeClient()
    private let proxy = ProxyClient()
    private let cache = AppCache.shared

    private var watchPage: WatchPage?
    private var visibleRelatedVideos: [Video] = []
    private var playerViewController: AVPlayerViewController?
    private var descriptionExpanded = false
    private var relatedExpansionWorkItem: DispatchWorkItem?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let relatedCollectionView: UICollectionView
    private let sidebarContainer = UIView()
    private let portraitRelatedLayout: UICollectionViewFlowLayout
    private let landscapeRelatedLayout: UICollectionViewFlowLayout

    private let playerContainer = UIView()
    private let playerSpinner = UIActivityIndicatorView(style: .whiteLarge)
    private let playerStatusLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let channelNameLabel = UILabel()
    private let channelMetaLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let descriptionLabel = UILabel()
    private let descriptionButton = UIButton(type: .system)
    private let commentsLabel = UILabel()

    private var playerAspectConstraint: NSLayoutConstraint!
    private var relatedHeightConstraint: NSLayoutConstraint!
    private var playerTopConstraint: NSLayoutConstraint!
    private var playerLeadingConstraint: NSLayoutConstraint!
    private var playerTrailingConstraint: NSLayoutConstraint!
    private var playerToSidebarConstraint: NSLayoutConstraint!
    private var scrollTopToPlayerConstraint: NSLayoutConstraint!
    private var scrollTrailingConstraint: NSLayoutConstraint!
    private var scrollToSidebarConstraint: NSLayoutConstraint!
    private var sidebarTopConstraint: NSLayoutConstraint!
    private var sidebarTrailingConstraint: NSLayoutConstraint!
    private var sidebarBottomConstraint: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var relatedPortraitConstraints: [NSLayoutConstraint] = []
    private var relatedLandscapeConstraints: [NSLayoutConstraint] = []
    private var isShowingLandscapeRelated = false

    init(video: Video) {
        let portraitLayout = UICollectionViewFlowLayout()
        portraitLayout.minimumLineSpacing = 12
        portraitLayout.minimumInteritemSpacing = 8
        portraitLayout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 16, right: 12)
        self.portraitRelatedLayout = portraitLayout

        let landscapeLayout = UICollectionViewFlowLayout()
        landscapeLayout.minimumLineSpacing = 12
        landscapeLayout.minimumInteritemSpacing = 0
        landscapeLayout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 12, right: 8)
        self.landscapeRelatedLayout = landscapeLayout

        self.relatedCollectionView = UICollectionView(frame: .zero, collectionViewLayout: portraitLayout)
        self.initialVideo = video
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialVideo.title
        setupLayout()
        applyTheme()
        loadInitialState()
        if let cachedPage = cache.cachedWatchPage(videoId: initialVideo.id) {
            applyWatchPage(cachedPage)
        } else {
            loadWatchPage()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForSize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateLayoutForSize(size)
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.updateLayoutForSize()
        })
    }

    @objc private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        scrollView.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        relatedCollectionView.backgroundColor = theme.background
        sidebarContainer.backgroundColor = theme.background
        titleLabel.textColor = theme.primaryText
        metaLabel.textColor = theme.secondaryText
        channelNameLabel.textColor = theme.primaryText
        channelMetaLabel.textColor = theme.secondaryText
        descriptionLabel.textColor = theme.secondaryText
        descriptionButton.setTitleColor(theme.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1), for: .normal)
        commentsLabel.textColor = theme.secondaryText
        playerContainer.backgroundColor = .black
        playerStatusLabel.textColor = .lightGray

        if subscribeButton.currentTitle == "Subscribed" {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(theme.primaryText, for: .normal)
        } else {
            subscribeButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.cancelsTouchesInView = false
        view.addSubview(scrollView)

        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerContainer)
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarContainer)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        scrollTrailingConstraint = scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        scrollToSidebarConstraint = scrollView.trailingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor)
        playerTopConstraint = playerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        playerLeadingConstraint = playerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        playerTrailingConstraint = playerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        playerToSidebarConstraint = playerContainer.trailingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor)
        scrollTopToPlayerConstraint = scrollView.topAnchor.constraint(equalTo: playerContainer.bottomAnchor)
        sidebarTopConstraint = sidebarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        sidebarTrailingConstraint = sidebarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        sidebarBottomConstraint = sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 340)
        playerAspectConstraint = playerContainer.heightAnchor.constraint(equalTo: playerContainer.widthAnchor, multiplier: 9.0 / 16.0)

        NSLayoutConstraint.activate([
            playerTopConstraint,
            playerLeadingConstraint,
            playerTrailingConstraint,
            playerAspectConstraint,

            scrollTopToPlayerConstraint,
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollTrailingConstraint,
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        playerSpinner.translatesAutoresizingMaskIntoConstraints = false
        playerSpinner.startAnimating()
        playerContainer.addSubview(playerSpinner)

        playerStatusLabel.text = "Preparing video..."
        playerStatusLabel.textAlignment = .center
        playerStatusLabel.numberOfLines = 0
        playerStatusLabel.font = UIFont.systemFont(ofSize: 14)
        playerStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(playerStatusLabel)

        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        metaLabel.font = UIFont.systemFont(ofSize: 13)
        metaLabel.numberOfLines = 0
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaLabel)

        channelAvatarView.layer.cornerRadius = 22
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.translatesAutoresizingMaskIntoConstraints = false
        channelAvatarView.isUserInteractionEnabled = true
        contentView.addSubview(channelAvatarView)

        channelNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        channelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        channelNameLabel.isUserInteractionEnabled = true
        contentView.addSubview(channelNameLabel)

        channelMetaLabel.font = UIFont.systemFont(ofSize: 12)
        channelMetaLabel.numberOfLines = 2
        channelMetaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelMetaLabel)

        subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        subscribeButton.isEnabled = false
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subscribeButton)

        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.numberOfLines = 3
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)

        descriptionButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        descriptionButton.contentHorizontalAlignment = .left
        descriptionButton.translatesAutoresizingMaskIntoConstraints = false
        descriptionButton.addTarget(self, action: #selector(toggleDescription), for: .touchUpInside)
        contentView.addSubview(descriptionButton)

        commentsLabel.font = UIFont.systemFont(ofSize: 13)
        commentsLabel.numberOfLines = 0
        commentsLabel.translatesAutoresizingMaskIntoConstraints = false
        commentsLabel.text = "Comments are not wired yet."
        contentView.addSubview(commentsLabel)

        relatedCollectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)
        relatedCollectionView.dataSource = self
        relatedCollectionView.delegate = self
        relatedCollectionView.translatesAutoresizingMaskIntoConstraints = false
        relatedCollectionView.isScrollEnabled = false
        contentView.addSubview(relatedCollectionView)
        relatedHeightConstraint = relatedCollectionView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            playerSpinner.centerXAnchor.constraint(equalTo: playerContainer.centerXAnchor),
            playerSpinner.centerYAnchor.constraint(equalTo: playerContainer.centerYAnchor, constant: -10),
            playerStatusLabel.topAnchor.constraint(equalTo: playerSpinner.bottomAnchor, constant: 14),
            playerStatusLabel.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor, constant: 24),
            playerStatusLabel.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            channelAvatarView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 16),
            channelAvatarView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelAvatarView.widthAnchor.constraint(equalToConstant: 44),
            channelAvatarView.heightAnchor.constraint(equalToConstant: 44),

            channelNameLabel.topAnchor.constraint(equalTo: channelAvatarView.topAnchor, constant: 1),
            channelNameLabel.leadingAnchor.constraint(equalTo: channelAvatarView.trailingAnchor, constant: 12),
            channelNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: subscribeButton.leadingAnchor, constant: -12),

            channelMetaLabel.topAnchor.constraint(equalTo: channelNameLabel.bottomAnchor, constant: 3),
            channelMetaLabel.leadingAnchor.constraint(equalTo: channelNameLabel.leadingAnchor),
            channelMetaLabel.trailingAnchor.constraint(equalTo: channelNameLabel.trailingAnchor),

            subscribeButton.centerYAnchor.constraint(equalTo: channelAvatarView.centerYAnchor),
            subscribeButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: channelAvatarView.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            descriptionButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            descriptionButton.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor),
            descriptionButton.trailingAnchor.constraint(equalTo: descriptionLabel.trailingAnchor),

            commentsLabel.topAnchor.constraint(equalTo: descriptionButton.bottomAnchor, constant: 20),
            commentsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            commentsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        relatedPortraitConstraints = [
            relatedCollectionView.topAnchor.constraint(equalTo: commentsLabel.bottomAnchor, constant: 20),
            relatedCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            relatedCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            relatedHeightConstraint,
            relatedCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ]
        NSLayoutConstraint.activate(relatedPortraitConstraints)

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(openChannel))
        channelAvatarView.addGestureRecognizer(avatarTap)

        let labelTap = UITapGestureRecognizer(target: self, action: #selector(openChannel))
        channelNameLabel.addGestureRecognizer(labelTap)
    }

    private func updateRelatedLayout(isLandscape: Bool, containerSize: CGSize? = nil) {
        let layout = isLandscape ? landscapeRelatedLayout : portraitRelatedLayout
        if isLandscape {
            layout.minimumLineSpacing = 8
            layout.minimumInteritemSpacing = 0
            layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 12, right: 8)
        } else {
            layout.minimumLineSpacing = 8
            layout.minimumInteritemSpacing = 6
            layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 12, right: 8)
        }

        let columns: CGFloat = isLandscape ? 1 : 2
        let inset = layout.sectionInset.left + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing * (columns - 1)
        let baseWidth: CGFloat
        if let containerSize {
            baseWidth = isLandscape ? sidebarWidthConstraint.constant : containerSize.width
        } else {
            baseWidth = relatedCollectionView.bounds.width
        }
        let availableWidth = max(baseWidth - inset - spacing, 120)
        let itemWidth = floor(availableWidth / columns)
        let itemHeight = itemWidth * (9.0 / 16.0) + 90
        let size = CGSize(width: itemWidth, height: itemHeight)
        if layout.itemSize != size {
            layout.itemSize = size
        }

        let count = CGFloat(visibleRelatedVideos.count)
        let rows = count == 0 ? 0 : ceil(count / columns)
        let totalHeight = rows == 0 ? 0 : layout.sectionInset.top + layout.sectionInset.bottom + rows * itemHeight + max(0, rows - 1) * layout.minimumLineSpacing
        let desiredHeight = isLandscape ? 0 : totalHeight
        if relatedHeightConstraint.constant != desiredHeight {
            relatedHeightConstraint.constant = desiredHeight
        }

        layout.invalidateLayout()
    }

    private func moveRelatedCollection(toLandscape isLandscape: Bool) {
        guard isShowingLandscapeRelated != isLandscape else { return }

        NSLayoutConstraint.deactivate(isLandscape ? relatedPortraitConstraints : relatedLandscapeConstraints)
        relatedCollectionView.removeFromSuperview()

        if isLandscape {
            relatedCollectionView.isScrollEnabled = true
            sidebarContainer.addSubview(relatedCollectionView)
            relatedLandscapeConstraints = [
                relatedCollectionView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
                relatedCollectionView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
                relatedCollectionView.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
                relatedCollectionView.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
            ]
            NSLayoutConstraint.activate(relatedLandscapeConstraints)
        } else {
            relatedCollectionView.isScrollEnabled = false
            contentView.addSubview(relatedCollectionView)
            NSLayoutConstraint.activate(relatedPortraitConstraints)
        }

        isShowingLandscapeRelated = isLandscape
    }

    private func updateLayoutForSize(_ size: CGSize? = nil) {
        let resolvedSize = size ?? view.bounds.size
        let isLandscape = resolvedSize.width > resolvedSize.height
        if isLandscape {
            scrollTrailingConstraint.isActive = false
            scrollToSidebarConstraint.isActive = true
            sidebarTopConstraint.isActive = true
            sidebarTrailingConstraint.isActive = true
            sidebarBottomConstraint.isActive = true
            sidebarWidthConstraint.isActive = true
            sidebarContainer.isHidden = false
            playerTrailingConstraint.isActive = false
            playerToSidebarConstraint.isActive = true
        } else {
            scrollToSidebarConstraint.isActive = false
            scrollTrailingConstraint.isActive = true
            sidebarTopConstraint.isActive = false
            sidebarTrailingConstraint.isActive = false
            sidebarBottomConstraint.isActive = false
            sidebarWidthConstraint.isActive = false
            sidebarContainer.isHidden = true
            playerToSidebarConstraint.isActive = false
            playerTrailingConstraint.isActive = true
        }

        moveRelatedCollection(toLandscape: isLandscape)
        relatedCollectionView.backgroundColor = ThemeManager.shared.background
        let expectedLayout = isLandscape ? landscapeRelatedLayout : portraitRelatedLayout
        if relatedCollectionView.collectionViewLayout !== expectedLayout {
            relatedCollectionView.setCollectionViewLayout(expectedLayout, animated: false)
        }
        if !isLandscape {
            relatedCollectionView.alpha = 1
        }
        view.bringSubviewToFront(playerContainer)
        view.bringSubviewToFront(sidebarContainer)
        if let superview = relatedCollectionView.superview {
            superview.setNeedsLayout()
            superview.layoutIfNeeded()
        }
        if relatedCollectionView.bounds.width > 0 {
            updateRelatedLayout(isLandscape: isLandscape, containerSize: resolvedSize)
        }
    }

    private func loadInitialState() {
        titleLabel.text = initialVideo.title
        metaLabel.text = [initialVideo.viewCount, initialVideo.publishedAt.map(VideoFormatters.formatRelativeDate)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        channelNameLabel.text = initialVideo.channelName
        channelMetaLabel.text = nil
        subscribeButton.setTitle("Subscribe", for: .normal)
        descriptionLabel.text = nil
        descriptionButton.isHidden = true

        if let avatarURL = initialVideo.channelAvatarURL, let url = URL(string: avatarURL) {
            channelAvatarView.setImage(url: url)
        } else if let channelId = initialVideo.channelId {
            ChannelInfoStore.shared.fetch(channelId: channelId) { [weak self] result in
                guard let self = self,
                      case .success(let info) = result,
                      let avatarURL = info.avatarURL,
                      let url = URL(string: avatarURL)
                else { return }
                self.channelAvatarView.setImage(url: url)
            }
        } else {
            channelAvatarView.cancel()
        }

        startPlayback()
    }

    private func loadWatchPage() {
        client.fetchWatchPage(video: initialVideo) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.applyWatchPage(page)
                case .failure(let error):
                    print("[WatchViewController] watch page load failed \(self?.initialVideo.id ?? "nil"): \(error)")
                }
            }
        }
    }

    private func applyWatchPage(_ page: WatchPage) {
        relatedExpansionWorkItem?.cancel()
        watchPage = page
        cache.setWatchPage(page, videoId: initialVideo.id)
        title = page.video.title
        titleLabel.text = page.video.title
        metaLabel.text = [page.video.viewCount, page.video.publishedAt.map(VideoFormatters.formatRelativeDate)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        if let channelInfo = page.channelInfo {
            channelNameLabel.text = channelInfo.title.isEmpty ? initialVideo.channelName : channelInfo.title
            channelMetaLabel.text = channelInfo.subscriberCountText

            if let avatarURL = channelInfo.avatarURL, let url = URL(string: avatarURL) {
                channelAvatarView.setImage(url: url)
            } else if let channelId = page.video.channelId {
                ChannelInfoStore.shared.fetch(channelId: channelId) { [weak self] result in
                    guard let self = self,
                          case .success(let info) = result,
                          let avatarURL = info.avatarURL,
                          let url = URL(string: avatarURL)
                    else { return }
                    self.channelAvatarView.setImage(url: url)
                }
            }
        }

        subscribeButton.setTitle(page.subscribeButtonText ?? (page.isSubscribed ? "Subscribed" : "Subscribe"), for: .normal)
        descriptionLabel.text = page.description
        descriptionExpanded = false
        updateDescriptionUI()
        applyTheme()
        visibleRelatedVideos = Array(page.relatedVideos.prefix(3))
        relatedCollectionView.reloadData()
        scheduleRelatedExpansion(for: page)
        ChannelInfoStore.shared.preload(channelIds: page.relatedVideos.compactMap(\.channelId))
        view.setNeedsLayout()
    }

    private func scheduleRelatedExpansion(for page: WatchPage) {
        guard page.relatedVideos.count > visibleRelatedVideos.count else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.watchPage?.video.id == page.video.id else { return }
            self.visibleRelatedVideos = page.relatedVideos
            self.relatedCollectionView.reloadData()
            self.view.setNeedsLayout()
        }
        relatedExpansionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func startPlayback() {
        proxy.createSession(videoId: initialVideo.id) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.showPlaybackError(error.localizedDescription)
            case .success(let session):
                DispatchQueue.main.async {
                    self?.playerStatusLabel.text = session.ready ? "Ready, loading player..." : "Downloading video..."
                }

                self?.proxy.waitUntilReady(session: session) { result in
                    switch result {
                    case .failure(let error):
                        self?.showPlaybackError(error.localizedDescription)
                    case .success(let url):
                        DispatchQueue.main.async {
                            self?.attachPlayer(url: url)
                        }
                    }
                }
            }
        }
    }

    private func attachPlayer(url: URL) {
        playerSpinner.stopAnimating()
        playerStatusLabel.isHidden = true

        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true
        playerVC.view.isUserInteractionEnabled = true

        addChild(playerVC)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlayerTap))
        tap.cancelsTouchesInView = false
        playerVC.view.addGestureRecognizer(tap)
        playerContainer.addSubview(playerVC.view)
        playerContainer.bringSubviewToFront(playerVC.view)
        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])
        playerVC.didMove(toParent: self)
        player.play()
        playerViewController = playerVC
    }

    private func showPlaybackError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.playerSpinner.stopAnimating()
            self?.playerStatusLabel.text = "Playback error: \(message)"
            self?.playerStatusLabel.textColor = .systemRed
        }
    }

    private func updateDescriptionUI() {
        let text = descriptionLabel.text ?? ""
        let shouldCollapse = text.count > 140 || text.contains("\n")
        descriptionLabel.numberOfLines = descriptionExpanded ? 0 : 3
        descriptionButton.isHidden = !shouldCollapse
        descriptionButton.setTitle(descriptionExpanded ? "Show less" : "Show more", for: .normal)
        view.setNeedsLayout()
    }

    @objc private func toggleDescription() {
        descriptionExpanded.toggle()
        updateDescriptionUI()
    }

    @objc private func openChannel() {
        let sourceVideo = watchPage?.video ?? initialVideo
        guard let channelId = sourceVideo.channelId else { return }
        navigationController?.pushViewController(ChannelViewController(channelId: channelId,
                                                                      channelName: sourceVideo.channelName),
                                                 animated: true)
    }

    @objc private func handlePlayerTap() {
        guard let playerVC = playerViewController else { return }
        playerVC.showsPlaybackControls = false
        DispatchQueue.main.async {
            playerVC.showsPlaybackControls = true
        }
    }
}

extension WatchViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleRelatedVideos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseId, for: indexPath) as! VideoCell
        guard visibleRelatedVideos.indices.contains(indexPath.item) else { return cell }
        let video = visibleRelatedVideos[indexPath.item]
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

extension WatchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleRelatedVideos.indices.contains(indexPath.item) else { return }
        let video = visibleRelatedVideos[indexPath.item]
        navigationController?.pushViewController(WatchViewController(video: video), animated: true)
    }
}
