import UIKit
import AVKit

final class WatchViewController: UIViewController {

    private var initialVideo: Video
    private let client: VideoService = ServiceContainer.video
    private let cache = AppCache.shared

    private var watchPage: WatchPage?
    private var isSubscribed: Bool = false
    private var visibleRelatedVideos: [Video] = []
    private var comments: [Comment] = []
    private var commentsContinuation: String?
    private var playerViewController: AVPlayerViewController?
    private var videoPlayerView: VideoPlayerView?
    private var playerItemContext = 0
    private var activeDirectPlaybackClient: DirectPlaybackClient = .androidVR
    private var retriedDirectPlaybackWithWeb = false
    private var descriptionExpanded = false
    private var relatedExpansionWorkItem: DispatchWorkItem?
    private var isLoadingComments = false
    private var hlsPlaylistLoader: HLSPlaylistLoader?

    // SponsorBlock
    private let sponsorBlock = SponsorBlockController()

    // Quality switching context — set when HLS playback starts
    private var activePlaybackInfo: DirectPlaybackInfo?
    private var activePlaybackClient: DirectPlaybackClient = .androidVR
    private var activePlaybackHeaders: [String: String] = [:]
    private var activeVideoFormat: DashFormatInfo?
    private var backgroundRestoreTime: CMTime = .zero
    private var backgroundEnteredAt: Date?

    private var autoplayOverlay: AutoplayOverlayView?

    /// Token cancelled when the VC disappears — silences all in-flight network callbacks.
    private var pageLoadToken = CancellationToken()
    /// True while the outer scrollView is being dragged — prevents accidental cell taps.
    private var isOuterScrollViewDragging = false

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
    private let descriptionButton = UIButton(type: .system)  // "More"/"Less" toggle, positioned right of metaLabel
    private let commentsLabel = UILabel()
    private let commentsStackView = UIStackView()
    private let loadMoreCommentsButton = UIButton(type: .system)

    private let actionBar = UIStackView()
    private let likeButton = UIButton(type: .system)
    private let dislikeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let likeCountLabel = UILabel()
    private let dislikeCountLabel = UILabel()
    private var likeCount: String?
    private var dislikeCount: String?
    private var currentLikeStatus: LikeStatus = .indifferent

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
    private var contentBottomToCommentsConstraint: NSLayoutConstraint!
    private var relatedPortraitConstraints: [NSLayoutConstraint] = []
    private var relatedLandscapeConstraints: [NSLayoutConstraint] = []
    private var isShowingLandscapeRelated = false
    private var fullscreenSnapshot: (superview: UIView, frame: CGRect)?
    private var channelTopToMeta: NSLayoutConstraint!
    private var channelTopToDesc: NSLayoutConstraint!

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

    override var shouldAutorotate: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        applyTheme()
        setupNavigationBar()
        loadInitialState()
        // Always refresh watch page from network; cache used only for immediate display
        if let cachedPage = cache.cachedWatchPage(videoId: initialVideo.id) {
            applyWatchPage(cachedPage)
        }
        loadWatchPage()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    private func setupNavigationBar() {
        // Opaque nav bar — same look as the rest of the app
        let t = ThemeManager.shared
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = t.surface
            appearance.titleTextAttributes = [.foregroundColor: t.primaryText]
            navigationItem.standardAppearance = appearance
            navigationItem.scrollEdgeAppearance = appearance
        } else {
            navigationController?.navigationBar.barTintColor = t.surface
            navigationController?.navigationBar.isTranslucent = false
            navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: t.primaryText]
        }
        navigationController?.navigationBar.tintColor = t.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        navigationController?.setNavigationBarHidden(false, animated: false)

        let backBtn: UIBarButtonItem
        if #available(iOS 13.0, *) {
            let img = UIImage(systemName: "chevron.down",
                              withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
            backBtn = UIBarButtonItem(image: img, style: .plain, target: self, action: #selector(closeTapped))
        } else {
            // iOS 12: no SF Symbols — use a styled "✕" close indicator
            let btn = UIButton(type: .system)
            btn.setTitle("⌄", for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 26, weight: .semibold)
            btn.sizeToFit()
            btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            backBtn = UIBarButtonItem(customView: btn)
        }
        navigationItem.leftBarButtonItem = backBtn
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            pageLoadToken.cancel()
            playerViewController?.player?.pause()
            videoPlayerView?.player?.pause()
        }
    }

    @objc private func appDidEnterBackground() {
        let bgEnabled = BackgroundPlaybackService.isEnabled
        let hasVideoPlayer = videoPlayerView?.player != nil
        let hasPVCPlayer = playerViewController?.player != nil
        print("[WatchVC] appDidEnterBackground: bgEnabled=\(bgEnabled) videoPlayer=\(hasVideoPlayer) pvcPlayer=\(hasPVCPlayer)")
        if let player = videoPlayerView?.player {
            print("[WatchVC] videoPlayer rate=\(player.rate) status=\(player.status.rawValue) timeControlStatus=\(player.timeControlStatus.rawValue)")
        }

        guard bgEnabled else {
            playerViewController?.player?.pause()
            videoPlayerView?.player?.pause()
            return
        }

        // For generated HLS (video+audio): iOS suspends video segment downloads in background
        // causing -12889 timeouts that stall the player. Replace with audio-only HLS item
        // so only audio segments are fetched. Call play() synchronously so it fires before
        // the app fully suspends.
        if let player = videoPlayerView?.player,
           let loader = hlsPlaylistLoader {
            backgroundRestoreTime = player.currentTime()
            backgroundEnteredAt = Date()
            let audioMasterURL = URL(string: "\(HLSGenerator.scheme)://audio-master.m3u8")!
            let assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": activePlaybackHeaders]
            let audioAsset = AVURLAsset(url: audioMasterURL, options: assetOptions)
            audioAsset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
            let audioItem = AVPlayerItem(asset: audioAsset)
            audioItem.preferredForwardBufferDuration = 10.0
            player.replaceCurrentItem(with: audioItem)
            player.seek(to: backgroundRestoreTime, toleranceBefore: CMTime(seconds: 1, preferredTimescale: 1000), toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1000))
            player.play()
            print("[WatchVC] switched to audio-only HLS at \(CMTimeGetSeconds(backgroundRestoreTime))s")
        }
    }

    @objc private func appWillEnterForeground() {
        print("[WatchVC] appWillEnterForeground")

        guard BackgroundPlaybackService.isEnabled,
              let player = videoPlayerView?.player,
              let loader = hlsPlaylistLoader else {
            backgroundEnteredAt = nil
            return
        }

        // Restore video+audio HLS using wall-clock elapsed time for accurate position
        let elapsed = backgroundEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
        let restoreSeconds = CMTimeGetSeconds(backgroundRestoreTime) + elapsed
        let restoreTime = CMTime(seconds: restoreSeconds, preferredTimescale: 1000)
        backgroundEnteredAt = nil

        let masterURL = URL(string: "\(HLSGenerator.scheme)://master.m3u8")!
        let assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": activePlaybackHeaders]
        let asset = AVURLAsset(url: masterURL, options: assetOptions)
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
        player.replaceCurrentItem(with: item)
        player.seek(to: restoreTime, toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 1000), toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 1000)) { [weak player] _ in
            player?.play()
        }
        print("[WatchVC] restored video+audio HLS at \(restoreSeconds)s (base=\(CMTimeGetSeconds(backgroundRestoreTime))s + elapsed=\(String(format: "%.1f", elapsed))s)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let item = playerViewController?.player?.currentItem {
            stopObservingPlayerItem(item)
        }
        if let item = videoPlayerView?.player?.currentItem {
            stopObservingPlayerItem(item)
        }
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
        descriptionButton.setTitleColor(theme.secondaryText, for: .normal)
        commentsLabel.textColor = theme.primaryText
        loadMoreCommentsButton.setTitleColor(theme.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1), for: .normal)
        for btn in [likeButton, dislikeButton, shareButton, saveButton, downloadButton] {
            btn.tintColor = theme.primaryText
        }
        likeCountLabel.textColor = theme.secondaryText
        dislikeCountLabel.textColor = theme.secondaryText
        playerContainer.backgroundColor = .black
        playerStatusLabel.textColor = .lightGray

        if subscribeButton.currentTitle == "Subscribed" {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(theme.primaryText, for: .normal)
        } else {
            subscribeButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            subscribeButton.setTitleColor(.white, for: .normal)
        }

        // Update nav bar for theme changes
        if isViewLoaded && navigationController != nil {
            setupNavigationBar()
        }
        updateLikeDislikeUI()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.cancelsTouchesInView = false
        scrollView.delegate = self
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
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        subscribeButton.addTarget(self, action: #selector(subscribeButtonTapped), for: .touchUpInside)
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subscribeButton)

        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.isHidden = true
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)

        descriptionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        descriptionButton.translatesAutoresizingMaskIntoConstraints = false
        descriptionButton.addTarget(self, action: #selector(toggleDescription), for: .touchUpInside)
        descriptionButton.setTitle("More", for: .normal)
        contentView.addSubview(descriptionButton)

        // Action bar — each item is a vertical UIStackView: [imageButton, label]
        actionBar.axis = .horizontal
        actionBar.distribution = .fillEqually
        actionBar.spacing = 8
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionBar)

        func actionIcon(_ name: String) -> UIImage? {
            guard let img = UIImage(named: name) else { return nil }
            let size = CGSize(width: 22, height: 22)
            return UIGraphicsImageRenderer(size: size).image { _ in
                img.draw(in: CGRect(origin: .zero, size: size))
            }.withRenderingMode(.alwaysTemplate)
        }

        func makeActionItem(btn: UIButton, countLabel: UILabel? = nil, iconName: String, staticLabel: String?) -> UIStackView {
            btn.setImage(actionIcon(iconName), for: .normal)
            btn.tintColor = ThemeManager.shared.primaryText
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true

            let label = countLabel ?? UILabel()
            label.font = UIFont.systemFont(ofSize: 11)
            label.textAlignment = .center
            label.textColor = ThemeManager.shared.secondaryText
            label.text = staticLabel ?? "—"
            label.translatesAutoresizingMaskIntoConstraints = false

            let stack = UIStackView(arrangedSubviews: [btn, label])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        }

        actionBar.addArrangedSubview(makeActionItem(btn: likeButton,    countLabel: likeCountLabel,    iconName: "icon_thumb_up",   staticLabel: nil))
        actionBar.addArrangedSubview(makeActionItem(btn: dislikeButton, countLabel: dislikeCountLabel, iconName: "icon_thumb_down", staticLabel: nil))
        actionBar.addArrangedSubview(makeActionItem(btn: shareButton,   countLabel: nil,               iconName: "icon_share",      staticLabel: "Share"))
        actionBar.addArrangedSubview(makeActionItem(btn: saveButton,    countLabel: nil,               iconName: "icon_bookmark",   staticLabel: "Save"))
        actionBar.addArrangedSubview(makeActionItem(btn: downloadButton,countLabel: nil,               iconName: "icon_download",   staticLabel: "Download"))
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        dislikeButton.addTarget(self, action: #selector(dislikeTapped), for: .touchUpInside)

        commentsLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        commentsLabel.numberOfLines = 0
        commentsLabel.translatesAutoresizingMaskIntoConstraints = false
        commentsLabel.text = "Comments"
        contentView.addSubview(commentsLabel)

        commentsStackView.axis = .vertical
        commentsStackView.spacing = 12
        commentsStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(commentsStackView)

        loadMoreCommentsButton.translatesAutoresizingMaskIntoConstraints = false
        loadMoreCommentsButton.contentHorizontalAlignment = .left
        loadMoreCommentsButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        loadMoreCommentsButton.setTitle("Load more comments", for: .normal)
        loadMoreCommentsButton.addTarget(self, action: #selector(loadMoreCommentsTapped), for: .touchUpInside)
        contentView.addSubview(loadMoreCommentsButton)

        relatedCollectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)
        relatedCollectionView.dataSource = self
        relatedCollectionView.delegate = self
        relatedCollectionView.translatesAutoresizingMaskIntoConstraints = false
        relatedCollectionView.isScrollEnabled = false
        contentView.addSubview(relatedCollectionView)
        relatedHeightConstraint = relatedCollectionView.heightAnchor.constraint(equalToConstant: 0)
        relatedHeightConstraint.priority = .defaultHigh  // allows other constraints to win when related videos load

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
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: descriptionButton.leadingAnchor, constant: -8),

            descriptionButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionButton.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

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

            actionBar.topAnchor.constraint(equalTo: channelAvatarView.bottomAnchor, constant: 16),
            actionBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 52),

            commentsLabel.topAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: 20),
            commentsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            commentsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            commentsStackView.topAnchor.constraint(equalTo: commentsLabel.bottomAnchor, constant: 12),
            commentsStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            commentsStackView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

        loadMoreCommentsButton.topAnchor.constraint(equalTo: commentsStackView.bottomAnchor, constant: 12),
        loadMoreCommentsButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        loadMoreCommentsButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        channelTopToMeta = channelAvatarView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 16)
        channelTopToDesc = channelAvatarView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 12)
        channelTopToMeta.isActive = true

        contentBottomToCommentsConstraint = loadMoreCommentsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)

        relatedPortraitConstraints = [
            relatedCollectionView.topAnchor.constraint(equalTo: loadMoreCommentsButton.bottomAnchor, constant: 20),
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
        let itemHeight = itemWidth * (9.0 / 16.0) + 92
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
            // Move related collection first (deactivates relatedPortraitConstraints),
            // then activate contentBottomToCommentsConstraint to avoid brief conflict
            moveRelatedCollection(toLandscape: true)
            contentBottomToCommentsConstraint.isActive = true
        } else {
            // Deactivate contentBottomToCommentsConstraint first before activating portrait constraints
            contentBottomToCommentsConstraint.isActive = false
            scrollToSidebarConstraint.isActive = false
            scrollTrailingConstraint.isActive = true
            sidebarTopConstraint.isActive = false
            sidebarTrailingConstraint.isActive = false
            sidebarBottomConstraint.isActive = false
            sidebarWidthConstraint.isActive = false
            sidebarContainer.isHidden = true
            playerToSidebarConstraint.isActive = false
            playerTrailingConstraint.isActive = true
            moveRelatedCollection(toLandscape: false)
        }
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
        // Hide until we have real subscription state from the network
        subscribeButton.isHidden = !OAuthClient.shared.isAnonymous
        subscribeButton.setTitle("Subscribe", for: .normal)
        descriptionLabel.text = nil
        descriptionButton.isHidden = true
        resetComments()

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
        client.fetchWatchPage(video: initialVideo, cancellationToken: pageLoadToken) { [weak self] result in
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

    @objc private func closeTapped() {
        exitFullscreenIfNeeded()
        dismiss(animated: true)
    }

    private func exitFullscreenIfNeeded() {
        guard fullscreenSnapshot != nil, let playerView = videoPlayerView else { return }
        exitFullscreen(playerView: playerView)
    }

    func loadVideo(_ video: Video) {
        dismissAutoplayOverlay()

        relatedExpansionWorkItem?.cancel()
        relatedExpansionWorkItem = nil

        pageLoadToken.cancel()
        pageLoadToken = CancellationToken()

        resetPlaybackSurfaces()
        hlsPlaylistLoader = nil
        activePlaybackInfo = nil
        activeVideoFormat = nil
        retriedDirectPlaybackWithWeb = false

        watchPage = nil
        visibleRelatedVideos = []
        comments = []
        commentsContinuation = nil
        isLoadingComments = false
        descriptionExpanded = false
        likeCountLabel.text = "—"
        dislikeCountLabel.text = "—"
        currentLikeStatus = .indifferent
        sponsorBlock.reset()

        commentsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        loadMoreCommentsButton.isHidden = true

        scrollView.setContentOffset(.zero, animated: false)

        exitFullscreenIfNeeded()

        initialVideo = video
        loadInitialState()
        loadWatchPage()
        applyTheme()
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
        isSubscribed = page.isSubscribed
        subscribeButton.isHidden = false
        descriptionLabel.text = page.description
        descriptionExpanded = false
        updateDescriptionUI()

        if let likeCount = page.likeCount {
            likeCountLabel.text = likeCount
        } else {
            likeCountLabel.text = "—"
        }
        dislikeCountLabel.text = "—"
        currentLikeStatus = page.likeStatus ?? .indifferent
        updateLikeDislikeUI()

        let videoId = page.video.id
        if ReturnYouTubeDislikeService.enabled {
            ReturnYouTubeDislikeService.shared.fetchVotes(videoId: videoId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, self.watchPage?.video.id == videoId else { return }
                    if case .success(let votes) = result {
                        func fmt(_ n: Int) -> String {
                            switch n {
                            case 0..<1_000: return "\(n)"
                            case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
                            default: return String(format: "%.1fM", Double(n) / 1_000_000)
                            }
                        }
                        self.likeCountLabel.text = fmt(votes.likes)
                        self.dislikeCountLabel.text = fmt(votes.dislikes)
                    }
                }
            }
        }
        if SponsorBlockService.enabled {
            SponsorBlockService.shared.fetchSegments(videoId: videoId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, self.watchPage?.video.id == videoId else { return }
                    if case .success(let segments) = result {
                        self.sponsorBlock.segments = segments
                        self.videoPlayerView?.setSponsorSegments(segments)
                    }
                }
            }
        }
        applyTheme()
        visibleRelatedVideos = Array(page.relatedVideos.prefix(3))
        relatedCollectionView.reloadData()
        scheduleRelatedExpansion(for: page)
        ChannelInfoStore.shared.preload(channelIds: page.relatedVideos.compactMap(\.channelId))
        resetComments()
        loadComments()
        view.setNeedsLayout()
    }

    private func resetComments() {
        comments = []
        commentsContinuation = nil
        isLoadingComments = false
        commentsLabel.text = "Comments"
        renderComments()
    }

    private func loadComments(continuation: String? = nil) {
        guard !isLoadingComments else { return }
        isLoadingComments = true
        loadMoreCommentsButton.isEnabled = false
        loadMoreCommentsButton.isHidden = comments.isEmpty
        loadMoreCommentsButton.setTitle("Loading comments...", for: .normal)
        if comments.isEmpty {
            commentsLabel.text = "Loading comments..."
            renderComments()
        }

        client.fetchComments(videoId: initialVideo.id, continuation: continuation, cancellationToken: pageLoadToken) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingComments = false
                switch result {
                case .failure(let error):
                    print("[WatchViewController] comments load failed \(self.initialVideo.id): \(error)")
                    if self.comments.isEmpty {
                        self.commentsLabel.text = "Comments unavailable"
                    }
                    self.renderComments()
                case .success(let page):
                    self.commentsContinuation = page.continuation
                    if continuation == nil {
                        self.comments = page.comments
                    } else {
                        let existingIds = Set(self.comments.map(\.id))
                        self.comments.append(contentsOf: page.comments.filter { !existingIds.contains($0.id) })
                    }
                    self.commentsLabel.text = page.title ?? "Comments"
                    self.renderComments()
                }
            }
        }
    }

    private func renderComments() {
        commentsStackView.arrangedSubviews.forEach { view in
            commentsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if comments.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.numberOfLines = 0
            emptyLabel.font = UIFont.systemFont(ofSize: 13)
            emptyLabel.textColor = ThemeManager.shared.secondaryText
            emptyLabel.text = isLoadingComments ? "Loading comments..." : "Comments are unavailable yet."
            commentsStackView.addArrangedSubview(emptyLabel)
        } else {
            for comment in comments {
                commentsStackView.addArrangedSubview(makeCommentView(comment))
            }
        }

        loadMoreCommentsButton.setTitle(isLoadingComments ? "Loading comments..." : "Load more comments", for: .normal)
        loadMoreCommentsButton.isEnabled = !isLoadingComments
        loadMoreCommentsButton.isHidden = commentsContinuation == nil
        view.setNeedsLayout()
    }

    private func makeCommentView(_ comment: Comment) -> UIView {
        CommentViewBuilder.makeCommentView(comment)
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
        startPlayback(using: .androidVR)
    }

    private func startPlayback(using client: DirectPlaybackClient) {
        activeDirectPlaybackClient = client
        playerStatusLabel.text = "Minting PoToken..."

        WebPoTokenService.shared.fetchSessionToken(identifier: initialVideo.id) { [weak self] tokenResult in
            guard let self, !self.pageLoadToken.isCancelled else { return }
            let poToken: String?
            switch tokenResult {
            case .success(let token): poToken = token
            case .failure(let error):
                print("[WatchViewController] PoToken mint failed: \(error), proceeding without")
                poToken = nil
            }

            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Resolving direct stream..."
            }
            self.client.fetchDirectPlayback(videoId: self.initialVideo.id, client: client, poToken: poToken,
                                            cancellationToken: self.pageLoadToken) { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.showPlaybackError(error.localizedDescription)
                case .success(let info):
                    self?.startDirectPlayback(info, client: client)
                }
            }
        }
    }

    private func startDirectPlayback(_ info: DirectPlaybackInfo, client: DirectPlaybackClient) {
        print("[WatchViewController] startDirectPlayback (\(client)): progressive=\(info.progressiveURL?.absoluteString.prefix(80) ?? "nil") hls=\(info.hlsManifestURL != nil) dash=\(info.dashManifestURL != nil) video=\(info.videoURL != nil) audio=\(info.audioURL != nil) sabr=\(info.serverAbrStreamingURL != nil) quality=\(info.qualityLabel ?? "nil") visitorData=\(info.visitorData?.prefix(20) ?? "nil")")

        // For clients that don't require JS player (Android), try direct playback first
        if info.progressiveURL != nil || info.hlsManifestURL != nil || info.dashManifestURL != nil || (info.videoURL != nil && info.audioURL != nil) {
            print("[WatchViewController] trying direct playback (skip onesie) for \(client)")
            playDirectStream(info, client: client)
            return
        }

        if let sabrURL = info.serverAbrStreamingURL {
            let videoUstreamerLength = info.videoPlaybackUstreamerConfig?.count ?? 0
            let onesieUstreamerLength = info.onesieUstreamerConfig?.count ?? 0
            print("[WatchViewController] SABR candidate available (\(client)): \(sabrURL.absoluteString.prefix(80)), ustreamer=\(info.hasVideoPlaybackUstreamerConfig), videoUstreamerLen=\(videoUstreamerLength), onesieUstreamerLen=\(onesieUstreamerLength)")
        }
        guard let visitorData = info.visitorData, !visitorData.isEmpty else {
            showPlaybackError("Missing visitor data for onesie playback.")
            return
        }

        DispatchQueue.main.async {
            self.playerStatusLabel.text = "Minting WebPO tokens..."
        }

        let group = DispatchGroup()
        var contentToken: String?

        group.enter()
        WebPoTokenService.shared.fetchSessionToken(identifier: self.initialVideo.id) { result in
            if case .success(let token) = result {
                contentToken = token
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let contentPlaybackNonce = Self.makeContentPlaybackNonce()

            guard let contentPoToken = contentToken, !contentPoToken.isEmpty else {
                self.showPlaybackError("Failed to mint content WebPO token")
                return
            }

            self.playerStatusLabel.text = "Fetching stream via onesie..."
            OnesieService.shared.fetchPlaybackBootstrap(
                videoId: self.initialVideo.id,
                visitorData: visitorData,
                poToken: contentPoToken,
                contentPlaybackNonce: contentPlaybackNonce
            ) { [weak self] onesieResult in
                guard let self else { return }

                switch onesieResult {
                    case .success(let bootstrap):
                        guard let refreshedInfo = InnertubeClient.parsePlayerJSON(bootstrap.playerJSON) else {
                            print("[WatchViewController] onesie player JSON parse failed")
                            self.showPlaybackError("Onesie returned an unusable player response.")
                            return
                        }
                        let effectiveInfo = DirectPlaybackInfo(
                            hlsManifestURL: refreshedInfo.hlsManifestURL,
                            dashManifestURL: refreshedInfo.dashManifestURL,
                            progressiveURL: refreshedInfo.progressiveURL,
                            videoURL: refreshedInfo.videoURL,
                            audioURL: refreshedInfo.audioURL,
                            serverAbrStreamingURL: refreshedInfo.serverAbrStreamingURL,
                            videoPlaybackUstreamerConfig: refreshedInfo.videoPlaybackUstreamerConfig ?? info.videoPlaybackUstreamerConfig,
                            onesieUstreamerConfig: refreshedInfo.onesieUstreamerConfig ?? info.onesieUstreamerConfig,
                            sabrVideoFormat: refreshedInfo.sabrVideoFormat,
                            sabrAudioFormat: refreshedInfo.sabrAudioFormat,
                            videoItag: refreshedInfo.videoItag,
                            audioItag: refreshedInfo.audioItag,
                            qualityLabel: refreshedInfo.qualityLabel,
                            visitorData: refreshedInfo.visitorData ?? info.visitorData,
                            hasVideoPlaybackUstreamerConfig: refreshedInfo.hasVideoPlaybackUstreamerConfig || info.hasVideoPlaybackUstreamerConfig,
                            dashVideoFormat: refreshedInfo.dashVideoFormat,
                            dashAudioFormat: refreshedInfo.dashAudioFormat,
                            allDashVideoFormats: refreshedInfo.allDashVideoFormats,
                            duration: refreshedInfo.duration
                        )
                        self.startOnesiePlayback(effectiveInfo,
                                                bootstrap: bootstrap,
                                                client: client,
                                                contentPoToken: contentPoToken,
                                                contentPlaybackNonce: contentPlaybackNonce)

                case .failure(let error):
                    print("[WatchViewController] onesie failed (\(error))")
                    self.showPlaybackError("Onesie bootstrap failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func playDirectStream(_ info: DirectPlaybackInfo, client: DirectPlaybackClient) {
        let mediaVisitorData = info.visitorData
        print("[WatchViewController] playDirectStream: hls=\(info.hlsManifestURL != nil) dash=\(info.dashManifestURL != nil) progressive=\(info.progressiveURL != nil) video+audio=\(info.videoURL != nil && info.audioURL != nil) sabr=\(info.serverAbrStreamingURL != nil)")

        if let hlsManifestURL = info.hlsManifestURL {
            print("[WatchViewController] choosing HLS: \(hlsManifestURL.absoluteString.prefix(120))...")
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading HLS stream..."
                self.attachPlayer(url: hlsManifestURL)
            }
            return
        }

        // Generated HLS from adaptive format info — instant 720p via native AVPlayer
        if let dashVideo = info.dashVideoFormat, let dashAudio = info.dashAudioFormat {
            activePlaybackInfo = info
            activePlaybackClient = client
            let videoURL = prepareDirectPlaybackURL(baseURL: dashVideo.url, client: client, poToken: nil)
            let audioURL = prepareDirectPlaybackURL(baseURL: dashAudio.url, client: client, poToken: nil)
            let quality = info.qualityLabel ?? "720p"
            let headers = makeDirectRequestHeaders(visitorData: mediaVisitorData, client: client)
            print("[WatchViewController] choosing generated HLS (\(quality)): video itag=\(dashVideo.itag) audio itag=\(dashAudio.itag)")
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading \(quality) stream..."
            }
            buildHLSAndPlay(videoURL: videoURL, audioURL: audioURL,
                            videoFormat: dashVideo, audioFormat: dashAudio,
                            headers: headers, quality: quality)
            return
        }

        if let progressiveURL = info.progressiveURL {
            let preparedURL = prepareDirectPlaybackURL(baseURL: progressiveURL, client: client, poToken: nil)
            print("[WatchViewController] starting progressive (360p) immediately")

            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading stream..."
                self.attachDirectPlayer(url: preparedURL, visitorData: mediaVisitorData, client: client)
            }

            // Background: prepare adaptive (720p) composition, then upgrade
            if let videoURL = info.videoURL, let audioURL = info.audioURL {
                let preparedVideoURL = prepareDirectPlaybackURL(baseURL: videoURL, client: client, poToken: nil)
                let preparedAudioURL = prepareDirectPlaybackURL(baseURL: audioURL, client: client, poToken: nil)
                let headers = makeDirectRequestHeaders(visitorData: mediaVisitorData, client: client)
                let quality = info.qualityLabel ?? "720p"
                print("[WatchViewController] background: preparing \(quality) adaptive...")
                prepareAdaptiveUpgrade(videoURL: preparedVideoURL, audioURL: preparedAudioURL, headers: headers, quality: quality)
            }
            return
        }

        // No progressive — try adaptive directly (will be slow but works)
        if let videoURL = info.videoURL, let audioURL = info.audioURL {
            let preparedVideoURL = prepareDirectPlaybackURL(baseURL: videoURL, client: client, poToken: nil)
            let preparedAudioURL = prepareDirectPlaybackURL(baseURL: audioURL, client: client, poToken: nil)
            let headers = makeDirectRequestHeaders(visitorData: mediaVisitorData, client: client)
            let quality = info.qualityLabel ?? "?"
            print("[WatchViewController] choosing adaptive (no progressive fallback): quality=\(quality)")
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading \(quality) stream..."
                self.attachComposedPlayer(videoURL: preparedVideoURL, audioURL: preparedAudioURL, headers: headers) { _ in }
            }
            return
        }

        showPlaybackError("No playable direct stream available.")
    }

    private func startOnesiePlayback(_ info: DirectPlaybackInfo,
                                     bootstrap: OnesiePlaybackBootstrap,
                                     client: DirectPlaybackClient,
                                     contentPoToken: String,
                                     contentPlaybackNonce: String) {
        let typeSummary = bootstrap.responseParts
            .map { "\($0.type)(c\($0.compressionType))" }
            .joined(separator: ",")
        print("[WatchViewController] onesie bootstrap ready proxy=\(bootstrap.proxyStatus) http=\(bootstrap.httpStatus) parts=[\(typeSummary)]")
        if info.hlsManifestURL != nil || info.progressiveURL != nil || (info.videoURL != nil && info.audioURL != nil) {
            playDirectStream(info, client: client)
            return
        }
        showPlaybackError("Onesie returned no playable streams.")
    }

    private static func makeContentPlaybackNonce(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    private func prepareDirectPlaybackURL(baseURL: URL, client: DirectPlaybackClient, poToken: String?) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "pot" || $0.name == "cver" }
        if let pot = poToken, !pot.isEmpty {
            items.append(URLQueryItem(name: "pot", value: pot))
        }
        items.append(URLQueryItem(name: "cver", value: client.clientVersion))
        components.queryItems = items
        let finalURL = components.url ?? baseURL
        print("[WatchViewController] direct URL prepared with pot/cver for \(client)")
        return finalURL
    }

    private func generateColdStartToken(identifier: String, clientState: UInt8 = 1) -> String? {
        guard let identifierData = identifier.data(using: .utf8), identifierData.count <= 118 else {
            return nil
        }

        let timestamp = UInt32(Date().timeIntervalSince1970)
        let key0 = UInt8.random(in: 0...255)
        let key1 = UInt8.random(in: 0...255)
        let header: [UInt8] = [
            key0,
            key1,
            0,
            clientState,
            UInt8((timestamp >> 24) & 0xFF),
            UInt8((timestamp >> 16) & 0xFF),
            UInt8((timestamp >> 8) & 0xFF),
            UInt8(timestamp & 0xFF)
        ]

        let payloadLength = header.count + identifierData.count
        guard payloadLength <= 255 else {
            return nil
        }

        var packet = Data([34, UInt8(payloadLength)])
        packet.append(contentsOf: header)
        packet.append(identifierData)

        var bytes = [UInt8](packet)
        let payloadStart = 2
        let keyLength = 2
        guard bytes.count > payloadStart + keyLength else {
            return nil
        }

        for index in (payloadStart + keyLength)..<bytes.count {
            bytes[index] ^= bytes[payloadStart + ((index - payloadStart) % keyLength)]
        }

        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func attachComposedPlayer(videoURL: URL, audioURL: URL,
                                      headers: [String: String],
                                      completion: @escaping (Bool) -> Void) {
        AdaptiveCompositionBuilder.build(videoURL: videoURL, audioURL: audioURL, headers: headers) { [weak self] item in
            guard let self = self, let item = item else {
                completion(false)
                return
            }
            self.attachPlayer(item: item, minimizeStalling: false)
            completion(true)
        }
    }

    private func prepareAdaptiveUpgrade(videoURL: URL, audioURL: URL, headers: [String: String], quality: String) {
        AdaptiveCompositionBuilder.build(videoURL: videoURL, audioURL: audioURL, headers: headers) { [weak self] item in
            guard let self = self, let item = item else { return }

            guard let player = self.videoPlayerView?.player ?? self.playerViewController?.player else { return }
            let currentTime = player.currentTime()
            let wasPlaying = player.rate > 0

            if let oldItem = player.currentItem {
                self.stopObservingPlayerItem(oldItem)
            }

            self.startObservingPlayerItem(item)
            player.replaceCurrentItem(with: item)
            player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying { player.play() }
            print("[WatchViewController] adaptive upgrade: switched to \(quality)")
        }
    }

    private func buildHLSAndPlay(videoURL: URL, audioURL: URL,
                                 videoFormat: DashFormatInfo, audioFormat: DashFormatInfo,
                                 headers: [String: String], quality: String) {
        activeVideoFormat = videoFormat
        activePlaybackHeaders = headers

        HLSPlaybackBuilder.build(videoURL: videoURL, audioURL: audioURL,
                                 videoFormat: videoFormat, audioFormat: audioFormat,
                                 headers: headers) { [weak self] result in
            guard let self = self else { return }
            guard let result = result else {
                self.fallbackToProgressivePlayback()
                return
            }
            DispatchQueue.main.async {
                self.hlsPlaylistLoader = result.loader
                self.attachPlayer(item: result.playerItem)
                print("[WatchViewController] HLS: player attached for \(quality)")
            }
        }
    }

    private func fallbackToProgressivePlayback() {
        print("[WatchViewController] HLS: falling back to progressive + adaptive upgrade")
        // Re-trigger playback without DASH format info to hit progressive path
        // For now just show error since we'd need stored playback info
        DispatchQueue.main.async {
            self.showPlaybackError("HLS generation failed — no fallback available")
        }
    }

    private func attachPlayer(url: URL) {
        attachPlayer(item: AVPlayerItem(url: url))
    }

    private func attachDirectPlayer(url: URL, visitorData: String?, client: DirectPlaybackClient) {
        resetPlaybackSurfaces()

        let headers = makeDirectRequestHeaders(visitorData: visitorData, client: client)
        print("[WatchViewController] attachDirectPlayer (\(client)): url=\(url.absoluteString.prefix(120))...")
        print("[WatchViewController] attachDirectPlayer headers: \(headers)")
        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        attachPlayer(item: item)
    }

    private func makeDirectRequestHeaders(visitorData: String?, client: DirectPlaybackClient) -> [String: String] {
        client.streamHeaders(visitorData: visitorData)
    }

    private func attachPlayer(item: AVPlayerItem, minimizeStalling: Bool = true) {
        guard !pageLoadToken.isCancelled else { return }
        resetPlaybackSurfaces()

        playerSpinner.stopAnimating()
        playerStatusLabel.isHidden = true

        startObservingPlayerItem(item)

        let player = AVPlayer(playerItem: item)
        if !minimizeStalling {
            player.automaticallyWaitsToMinimizeStalling = false
        }

        let pv = videoPlayerView ?? {
            let v = VideoPlayerView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.delegate = self
            playerContainer.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: playerContainer.topAnchor),
                v.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            ])
            videoPlayerView = v
            return v
        }()

        // Wire SponsorBlock callbacks
        sponsorBlock.attach(to: pv)
        pv.onTimeUpdate = { [weak self] time in self?.sponsorBlock.checkTime(time) }
        pv.onSkipTapped  = { [weak self] in self?.sponsorBlock.skipCurrentSegment() }
        if !sponsorBlock.segments.isEmpty {
            pv.setSponsorSegments(sponsorBlock.segments)
        }

        playerContainer.bringSubviewToFront(pv)
        pv.attach(player: player)
        player.play()
    }

    private func resetPlaybackSurfaces() {
        if let existingItem = playerViewController?.player?.currentItem {
            stopObservingPlayerItem(existingItem)
        }
        playerViewController?.player?.pause()
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil

        if let existing = videoPlayerView?.player?.currentItem {
            stopObservingPlayerItem(existing)
        }
        videoPlayerView?.detach()
        // Keep the view — reuse it on next attach
    }

    private func startObservingPlayerItem(_ item: AVPlayerItem) {
        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.initial, .new], context: &playerItemContext)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidFailToPlayToEnd(_:)),
                                               name: .AVPlayerItemFailedToPlayToEndTime,
                                               object: item)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemNewErrorLogEntry(_:)),
                                               name: .AVPlayerItemNewErrorLogEntry,
                                               object: item)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToEnd(_:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: item)
    }

    private func stopObservingPlayerItem(_ item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemNewErrorLogEntry, object: item)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), context: &playerItemContext)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &playerItemContext,
              keyPath == #keyPath(AVPlayerItem.status),
              let item = object as? AVPlayerItem else {
            // Do NOT call super — NSObject's Swift overlay fatals on unrecognised KVO
            return
        }

        switch item.status {
        case .readyToPlay:
            let duration = CMTimeGetSeconds(item.duration)
            let tracks = item.tracks.map { "\($0.assetTrack?.mediaType.rawValue ?? "?")" }.joined(separator: ",")
            print("[WatchViewController] player item ready: duration=\(duration)s tracks=[\(tracks)]")
        case .failed:
            let nsError = item.error as NSError?
            print("[WatchViewController] player item FAILED: \(item.error?.localizedDescription ?? "unknown") domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? 0)")
            if let underlyingError = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("[WatchViewController] underlying error: \(underlyingError.domain) code=\(underlyingError.code) \(underlyingError.localizedDescription)")
            }
        case .unknown:
            print("[WatchViewController] player item status unknown")
        @unknown default:
            print("[WatchViewController] player item status unexpected")
        }
    }

    @objc private func playerItemDidFailToPlayToEnd(_ note: Notification) {
        let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown"
        print("[WatchViewController] player item failed to end: \(error)")
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        guard let nextVideo = watchPage?.nextVideo else { return }
        showAutoplayOverlay(for: nextVideo)
    }

    private func showAutoplayOverlay(for video: Video) {
        autoplayOverlay?.removeFromSuperview()
        let overlay = AutoplayOverlayView(nextVideo: video, countdownSecs: 5)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.onPlay = { [weak self] in
            self?.dismissAutoplayOverlay()
            self?.loadVideo(video)
        }
        overlay.onCancel = { [weak self] in
            self?.dismissAutoplayOverlay()
        }
        playerContainer.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])
        autoplayOverlay = overlay
        UIView.animate(withDuration: 0.25) { overlay.alpha = 1 }
        overlay.startCountdown()
    }

    private func dismissAutoplayOverlay() {
        guard let overlay = autoplayOverlay else { return }
        autoplayOverlay = nil
        UIView.animate(withDuration: 0.2, animations: { overlay.alpha = 0 },
                       completion: { _ in overlay.removeFromSuperview() })
    }

    @objc private func playerItemNewErrorLogEntry(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem,
              let events = item.errorLog()?.events,
              let last = events.last else {
            print("[WatchViewController] player item new error log entry")
            return
        }

        print("[WatchViewController] player error log: domain=\(last.errorDomain ?? "nil"), code=\(last.errorStatusCode), comment=\(last.errorComment ?? "nil"), uri=\(last.uri ?? "nil")")
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
        let hasDesc = !text.isEmpty
        descriptionLabel.isHidden = !descriptionExpanded
        channelTopToMeta.isActive = !descriptionExpanded
        channelTopToDesc.isActive = descriptionExpanded
        descriptionButton.isHidden = !hasDesc
        descriptionButton.setTitle(descriptionExpanded ? "Less" : "More", for: .normal)
        view.setNeedsLayout()
    }

    @objc private func toggleDescription() {
        descriptionExpanded.toggle()
        updateDescriptionUI()
    }

    private func updateLikeDislikeUI() {
        let tint = ThemeManager.shared.primaryText
        let activeTint = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        likeButton.tintColor = currentLikeStatus == .like ? activeTint : tint
        likeCountLabel.textColor = currentLikeStatus == .like ? activeTint : ThemeManager.shared.secondaryText
        dislikeButton.tintColor = currentLikeStatus == .dislike ? activeTint : tint
        dislikeCountLabel.textColor = currentLikeStatus == .dislike ? activeTint : ThemeManager.shared.secondaryText
    }

    @objc private func subscribeButtonTapped() {
        guard let channelId = watchPage?.channelInfo?.id ?? watchPage?.video.channelId else { return }
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        subscribeButton.setTitle(isSubscribed ? "Subscribed" : "Subscribe", for: .normal)
        subscribeButton.isEnabled = false
        applyTheme()

        let completion: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.subscribeButton.isEnabled = true
                switch result {
                case .success:
                    print("[Subscribe] \(wasSubscribed ? "unsubscribed" : "subscribed") channelId=\(channelId)")
                case .failure(let e):
                    print("[Subscribe] \(wasSubscribed ? "unsubscribe" : "subscribe") failed channelId=\(channelId): \(e)")
                    self.isSubscribed = wasSubscribed
                    self.subscribeButton.setTitle(wasSubscribed ? "Subscribed" : "Subscribe", for: .normal)
                    self.applyTheme()
                }
            }
        }

        if wasSubscribed {
            client.unsubscribeFromChannel(channelId: channelId, completion: completion)
        } else {
            client.subscribeToChannel(channelId: channelId, completion: completion)
        }
    }

    @objc private func likeTapped() {
        guard let videoId = watchPage?.video.id else { return }
        let wasLiked = currentLikeStatus == .like
        let newStatus: LikeStatus = wasLiked ? .indifferent : .like
        print("[Like] tapped: \(wasLiked ? "removing like" : "sending like") for \(videoId)")
        currentLikeStatus = newStatus
        updateLikeDislikeUI()
        if wasLiked {
            client.removeLike(videoId: videoId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("[Like] removeLike success for \(videoId)")
                        if ReturnYouTubeDislikeService.enabled {
                            ReturnYouTubeDislikeService.shared.reportVote(videoId: videoId, value: 0)
                        }
                    case .failure(let e):
                        print("[Like] removeLike failed for \(videoId): \(e)")
                        self?.currentLikeStatus = .like
                        self?.updateLikeDislikeUI()
                    }
                }
            }
        } else {
            client.sendLike(videoId: videoId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("[Like] sendLike success for \(videoId)")
                        if ReturnYouTubeDislikeService.enabled {
                            ReturnYouTubeDislikeService.shared.reportVote(videoId: videoId, value: 1)
                        }
                    case .failure(let e):
                        print("[Like] sendLike failed for \(videoId): \(e)")
                        self?.currentLikeStatus = .indifferent
                        self?.updateLikeDislikeUI()
                    }
                }
            }
        }
    }

    @objc private func dislikeTapped() {
        guard let videoId = watchPage?.video.id else { return }
        let wasDisliked = currentLikeStatus == .dislike
        let newStatus: LikeStatus = wasDisliked ? .indifferent : .dislike
        print("[Like] tapped: \(wasDisliked ? "removing dislike" : "sending dislike") for \(videoId)")
        currentLikeStatus = newStatus
        updateLikeDislikeUI()
        if wasDisliked {
            client.removeLike(videoId: videoId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("[Like] removeDislike success for \(videoId)")
                        if ReturnYouTubeDislikeService.enabled {
                            ReturnYouTubeDislikeService.shared.reportVote(videoId: videoId, value: 0)
                        }
                    case .failure(let e):
                        print("[Like] removeDislike failed for \(videoId): \(e)")
                    }
                }
            }
        } else {
            client.sendDislike(videoId: videoId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("[Like] sendDislike success for \(videoId)")
                        if ReturnYouTubeDislikeService.enabled {
                            ReturnYouTubeDislikeService.shared.reportVote(videoId: videoId, value: -1)
                        }
                    case .failure(let e):
                        print("[Like] sendDislike failed for \(videoId): \(e)")
                    }
                }
            }
        }
    }

    @objc private func shareTapped() {
        let videoId = watchPage?.video.id ?? initialVideo.id
        guard let url = URL(string: "https://youtu.be/\(videoId)") else { return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(ac, animated: true)
    }

    @objc private func openChannel() {
        let sourceVideo = watchPage?.video ?? initialVideo
        guard let channelId = sourceVideo.channelId else { return }
        navigationController?.pushViewController(ChannelViewController(channelId: channelId,
                                                                      channelName: sourceVideo.channelName),
                                                 animated: true)
    }

    @objc private func loadMoreCommentsTapped() {
        guard let continuation = commentsContinuation else { return }
        loadComments(continuation: continuation)
    }

    @objc private func handlePlayerTap() {
        guard let playerVC = playerViewController else { return }
        playerVC.showsPlaybackControls = false
        DispatchQueue.main.async {
            playerVC.showsPlaybackControls = true
        }
    }
}

extension WatchViewController: VideoPlayerViewDelegate {
    func videoPlayerViewDidTapSettings(_ playerView: VideoPlayerView) {
        let alert = UIAlertController(title: "Playback settings", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Quality", style: .default) { [weak self] _ in
            self?.showQualityPicker()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = playerView
            pop.sourceRect = CGRect(x: playerView.bounds.maxX - 50, y: 20, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    func videoPlayerViewDidTapFullscreen(_ playerView: VideoPlayerView) {
        if playerView.isFullscreen {
            exitFullscreen(playerView: playerView)
        } else {
            enterFullscreen(playerView: playerView)
        }
    }

    private func enterFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window else { return }
        let frameInWindow = playerView.convert(playerView.bounds, to: window)
        fullscreenSnapshot = (superview: playerView.superview ?? view, frame: playerView.frame)

        playerView.removeFromSuperview()
        // Switch to frame-based layout for animation
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            playerView.frame = window.bounds
        }
    }

    private func exitFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else { return }

        let targetFrameInWindow = snap.superview.convert(snap.frame, to: window)

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
            playerView.frame = targetFrameInWindow
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = false
            snap.superview.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: snap.superview.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: snap.superview.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: snap.superview.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: snap.superview.bottomAnchor),
            ])
            playerView.isFullscreen = false
            self.fullscreenSnapshot = nil
        })
    }

    private func showQualityPicker() {
        guard let info = activePlaybackInfo,
              let audioFormat = info.dashAudioFormat else { return }

        let formats = info.allDashVideoFormats
        guard !formats.isEmpty else { return }

        let alert = UIAlertController(title: "Quality", message: nil, preferredStyle: .actionSheet)

        for format in formats {
            let label = qualityLabel(for: format)
            let isCurrent = format.itag == activeVideoFormat?.itag
            let title = isCurrent ? "✓ \(label)" : label
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self, format.itag != self.activeVideoFormat?.itag else { return }
                let client = self.activePlaybackClient
                let videoURL = self.prepareDirectPlaybackURL(baseURL: format.url, client: client, poToken: nil)
                let audioURL = self.prepareDirectPlaybackURL(baseURL: audioFormat.url, client: client, poToken: nil)
                DispatchQueue.main.async {
                    self.playerStatusLabel.text = "Loading \(label)..."
                    self.playerStatusLabel.isHidden = false
                }
                self.buildHLSAndPlay(videoURL: videoURL, audioURL: audioURL,
                                     videoFormat: format, audioFormat: audioFormat,
                                     headers: self.activePlaybackHeaders, quality: label)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = alert.popoverPresentationController,
           let playerView = videoPlayerView {
            pop.sourceView = playerView
            pop.sourceRect = CGRect(x: playerView.bounds.maxX - 50, y: 20, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func qualityLabel(for format: DashFormatInfo) -> String {
        guard let h = format.height else { return "itag \(format.itag)" }
        if let fps = format.fps, fps > 30 {
            return "\(h)p\(fps)"
        }
        return "\(h)p"
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
        let isLandscape = view.bounds.width > view.bounds.height
        cell.forceGridLayout = !isLandscape
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
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // Block selection while the outer scroll view is being dragged/scrolled
        // to prevent accidental video opens when the user intends to scroll.
        return !isOuterScrollViewDragging && !scrollView.isDecelerating
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleRelatedVideos.indices.contains(indexPath.item) else { return }
        let video = visibleRelatedVideos[indexPath.item]
        VideoRouter.shared.open(video: video, from: self)
    }
}

extension WatchViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        isOuterScrollViewDragging = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === self.scrollView else { return }
        if !decelerate { isOuterScrollViewDragging = false }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        isOuterScrollViewDragging = false
    }
}

