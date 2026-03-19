import UIKit
import AVKit
import WebKit

final class WatchViewController: UIViewController {

    private let initialVideo: Video
    private let client = InnertubeClient()
    private let cache = AppCache.shared

    private var watchPage: WatchPage?
    private var visibleRelatedVideos: [Video] = []
    private var comments: [Comment] = []
    private var commentsContinuation: String?
    private var playerViewController: AVPlayerViewController?
    private var directPlayerView: SZAVPlayer?
    private var manifestPlayerView: ManifestWebPlayerView?
    private var playerItemContext = 0
    private var activeDirectPlaybackClient: DirectPlaybackClient = .tvHTML5
    private var retriedDirectPlaybackWithWeb = false
    private var descriptionExpanded = false
    private var relatedExpansionWorkItem: DispatchWorkItem?
    private var isLoadingComments = false

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
    private let commentsStackView = UIStackView()
    private let loadMoreCommentsButton = UIButton(type: .system)

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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerViewController?.player?.pause()
        directPlayerView?.pause()
        manifestPlayerView?.stop()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        manifestPlayerView?.stop()
        if let item = playerViewController?.player?.currentItem {
            stopObservingPlayerItem(item)
        }
        directPlayerView?.reset(cleanAsset: true)
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
        commentsLabel.textColor = theme.primaryText
        loadMoreCommentsButton.setTitleColor(theme.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1), for: .normal)
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

            commentsStackView.topAnchor.constraint(equalTo: commentsLabel.bottomAnchor, constant: 12),
            commentsStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            commentsStackView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

        loadMoreCommentsButton.topAnchor.constraint(equalTo: commentsStackView.bottomAnchor, constant: 12),
        loadMoreCommentsButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        loadMoreCommentsButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

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
            contentBottomToCommentsConstraint.isActive = true
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
            contentBottomToCommentsConstraint.isActive = false
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

        client.fetchComments(videoId: initialVideo.id, continuation: continuation) { [weak self] result in
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
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarView = ThumbnailImageView(frame: .zero)
        avatarView.layer.cornerRadius = 16
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        if let urlString = comment.authorAvatarURL, let url = URL(string: urlString) {
            avatarView.setImage(url: url)
        }

        let authorLabel = UILabel()
        authorLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        authorLabel.textColor = ThemeManager.shared.primaryText
        authorLabel.numberOfLines = 1
        authorLabel.text = comment.isPinned ? "\(comment.authorName) • Pinned" : comment.authorName
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        let metaLabel = UILabel()
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.textColor = ThemeManager.shared.secondaryText
        metaLabel.numberOfLines = 0
        metaLabel.text = [comment.publishedTime, comment.likeCount.map { "\($0) likes" }, comment.replyCount.map { "\($0) replies" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentLabel = UILabel()
        contentLabel.font = UIFont.systemFont(ofSize: 13)
        contentLabel.textColor = ThemeManager.shared.primaryText
        contentLabel.numberOfLines = 0
        contentLabel.text = comment.content
        contentLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = ThemeManager.shared.separator

        container.addSubview(avatarView)
        container.addSubview(authorLabel)
        container.addSubview(metaLabel)
        container.addSubview(contentLabel)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: container.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            authorLabel.topAnchor.constraint(equalTo: container.topAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            contentLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 6),
            contentLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            separator.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
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
        startPlayback(using: .tvHTML5)
    }

    private func startPlayback(using client: DirectPlaybackClient) {
        activeDirectPlaybackClient = client
        playerStatusLabel.text = "Resolving direct stream..."
        self.client.fetchDirectPlayback(videoId: initialVideo.id, client: client) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.showPlaybackError(error.localizedDescription)
            case .success(let info):
                self?.startDirectPlayback(info, client: client)
            }
        }
    }

    private func startDirectPlayback(_ info: DirectPlaybackInfo, client: DirectPlaybackClient) {
        if let sabrURL = info.serverAbrStreamingURL {
            let videoUstreamerLength = info.videoPlaybackUstreamerConfig?.count ?? 0
            let onesieUstreamerLength = info.onesieUstreamerConfig?.count ?? 0
            print("[WatchViewController] SABR candidate available (\(client)): \(sabrURL.absoluteString), ustreamer=\(info.hasVideoPlaybackUstreamerConfig), videoUstreamerLen=\(videoUstreamerLength), onesieUstreamerLen=\(onesieUstreamerLength)")
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
                            hasVideoPlaybackUstreamerConfig: refreshedInfo.hasVideoPlaybackUstreamerConfig || info.hasVideoPlaybackUstreamerConfig
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

        if let hlsManifestURL = info.hlsManifestURL {
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading HLS stream..."
                self.attachPlayer(url: hlsManifestURL)
            }
            return
        }

        if let dashManifestURL = info.dashManifestURL {
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading DASH stream..."
                self.attachManifestPlayer(url: dashManifestURL)
            }
            return
        }

        if let progressiveURL = info.progressiveURL {
            let preparedURL = prepareDirectPlaybackURL(baseURL: progressiveURL, client: client, poToken: nil)
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading progressive stream..."
                self.attachDirectPlayer(url: preparedURL, visitorData: mediaVisitorData, client: client)
            }
            return
        }

        if let videoURL = info.videoURL, let audioURL = info.audioURL {
            let preparedVideoURL = prepareDirectPlaybackURL(baseURL: videoURL, client: client, poToken: nil)
            let preparedAudioURL = prepareDirectPlaybackURL(baseURL: audioURL, client: client, poToken: nil)
            let headers = makeDirectRequestHeaders(visitorData: mediaVisitorData, client: client)
            DispatchQueue.main.async {
                self.playerStatusLabel.text = "Loading adaptive stream..."
                self.attachComposedPlayer(videoURL: preparedVideoURL,
                                          audioURL: preparedAudioURL,
                                          headers: headers) { [weak self] success in
                    guard let self else { return }
                    if success {
                        return
                    }
                    if let progressiveURL = info.progressiveURL {
                        let preparedURL = self.prepareDirectPlaybackURL(baseURL: progressiveURL, client: client, poToken: nil)
                        self.playerStatusLabel.text = "Adaptive failed, loading progressive stream..."
                        self.attachDirectPlayer(url: preparedURL, visitorData: mediaVisitorData, client: client)
                    } else {
                        self.showPlaybackError("No playable direct stream available.")
                    }
                }
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
        if info.hlsManifestURL != nil || info.dashManifestURL != nil || info.progressiveURL != nil || (info.videoURL != nil && info.audioURL != nil) {
            playDirectStream(info, client: client)
            return
        }
        startSabrSessionIfPossible(info: info,
                                   bootstrap: bootstrap,
                                   client: client,
                                   contentPoToken: contentPoToken,
                                   contentPlaybackNonce: contentPlaybackNonce)
    }

    private func startSabrSessionIfPossible(info: DirectPlaybackInfo,
                                            bootstrap: OnesiePlaybackBootstrap,
                                            client: DirectPlaybackClient,
                                            contentPoToken: String,
                                            contentPlaybackNonce: String) {
        guard let streamingURL = info.serverAbrStreamingURL,
              let videoPlaybackUstreamerConfig = info.videoPlaybackUstreamerConfig,
              let videoPlaybackUstreamerConfigData = SabrProbeService.decodeWebSafeBase64(videoPlaybackUstreamerConfig),
              let audioFormat = info.sabrAudioFormat,
              let videoFormat = info.sabrVideoFormat
        else {
            showPlaybackError("Onesie succeeded, but SABR transport fields are missing.")
            return
        }

        DispatchQueue.main.async {
            self.playerStatusLabel.text = "Starting SABR session..."
        }

        let configuration = SabrSessionConfiguration(
            videoId: initialVideo.id,
            streamingURL: streamingURL,
            videoPlaybackUstreamerConfig: videoPlaybackUstreamerConfigData,
            contentPoToken: contentPoToken,
            contentPlaybackNonce: contentPlaybackNonce,
            client: client,
            visitorData: info.visitorData,
            audioFormat: audioFormat,
            videoFormat: videoFormat,
            bootstrapParts: bootstrap.responseParts
        )

        SabrSessionService.shared.startSession(configuration: configuration) { result in
            switch result {
            case .failure(let error):
                print("[WatchViewController] SABR session start failed (\(client)): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showPlaybackError("SABR session start failed: \(error.localizedDescription)")
                }
            case .success(let (session, response)):
                print("[WatchViewController] SABR session started (\(client)): id=\(session.id.uuidString) status=\(response.statusCode), contentType=\(response.contentType ?? "nil"), bytes=\(response.bodySize), parts=\(response.umpPartTypes)")
                if response.statusCode >= 400 {
                    DispatchQueue.main.async {
                        self.showPlaybackError("SABR startup rejected with HTTP \(response.statusCode).")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.playerStatusLabel.text = "SABR startup accepted. Media transport is next."
                    }
                }
            }
        }
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
        let cver: String
        switch client {
        case .tvHTML5:
            cver = DirectPlaybackClient.tvHTML5.clientVersion
        case .web:
            cver = DirectPlaybackClient.web.clientVersion
        case .android:
            cver = DirectPlaybackClient.android.clientVersion
        }
        items.append(URLQueryItem(name: "cver", value: cver))
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

    private func attachComposedPlayer(videoURL: URL,
                                      audioURL: URL,
                                      headers: [String: String],
                                      completion: @escaping (Bool) -> Void) {
        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let videoAsset = AVURLAsset(url: videoURL, options: assetOptions)
        let audioAsset = AVURLAsset(url: audioURL, options: assetOptions)
        let group = DispatchGroup()
        let keys = ["tracks", "duration", "playable"]
        var loadError = false

        for key in keys {
            group.enter()
            videoAsset.loadValuesAsynchronously(forKeys: [key]) {
                var error: NSError?
                let status = videoAsset.statusOfValue(forKey: key, error: &error)
                if status != .loaded {
                    print("[WatchViewController] direct video asset key failed \(key): \(error?.localizedDescription ?? "unknown")")
                    loadError = true
                }
                group.leave()
            }

            group.enter()
            audioAsset.loadValuesAsynchronously(forKeys: [key]) {
                var error: NSError?
                let status = audioAsset.statusOfValue(forKey: key, error: &error)
                if status != .loaded {
                    print("[WatchViewController] direct audio asset key failed \(key): \(error?.localizedDescription ?? "unknown")")
                    loadError = true
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, !loadError else {
                completion(false)
                return
            }

            guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first,
                  let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first
            else {
                completion(false)
                return
            }

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                completion(false)
                return
            }

            let duration = CMTimeMinimum(videoAsset.duration, audioAsset.duration)

            do {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
                videoTrack.preferredTransform = sourceVideoTrack.preferredTransform
            } catch {
                print("[WatchViewController] direct composition failed: \(error)")
                completion(false)
                return
            }

            let item = AVPlayerItem(asset: composition)
            self.attachPlayer(item: item)
            completion(true)
        }
    }

    private func attachPlayer(url: URL) {
        attachPlayer(item: AVPlayerItem(url: url))
    }

    private func attachManifestPlayer(url: URL) {
        resetPlaybackSurfaces()

        let playerView = manifestPlayerView ?? {
            let view = ManifestWebPlayerView()
            view.translatesAutoresizingMaskIntoConstraints = false
            playerContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: playerContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            ])
            manifestPlayerView = view
            return view
        }()

        playerSpinner.stopAnimating()
        playerStatusLabel.isHidden = true
        playerContainer.bringSubviewToFront(playerView)
        playerView.load(manifestURL: url) { [weak self] message in
            self?.showPlaybackError(message)
        }
    }

    private func attachDirectPlayer(url: URL, visitorData: String?, client: DirectPlaybackClient) {
        resetPlaybackSurfaces()

        let headers = makeDirectRequestHeaders(visitorData: visitorData, client: client)
        print("[WatchViewController] direct request headers (\(client)): \(headers)")
        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        attachPlayer(item: item)
    }

    private func makeDirectRequestHeaders(visitorData: String?, client: DirectPlaybackClient) -> [String: String] {
        var headers: [String: String]
        switch client {
        case .tvHTML5:
            headers = [
                "Accept": "*/*",
                "Accept-Language": "*",
                "User-Agent": "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
                "Referer": "https://www.youtube.com/tv",
                "Origin": "https://www.youtube.com",
                "X-Origin": "https://www.youtube.com",
                "X-Youtube-Client-Name": DirectPlaybackClient.tvHTML5.clientHeaderName,
                "X-Youtube-Client-Version": DirectPlaybackClient.tvHTML5.clientVersion
            ]
        case .web:
            headers = [
                "Accept": "*/*",
                "Accept-Language": "*",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                "Referer": "https://www.youtube.com/",
                "Origin": "https://www.youtube.com",
                "X-Origin": "https://www.youtube.com",
                "X-Youtube-Client-Name": DirectPlaybackClient.web.clientHeaderName,
                "X-Youtube-Client-Version": DirectPlaybackClient.web.clientVersion
            ]
        case .android:
            headers = [
                "Accept": "*/*",
                "Accept-Language": "*",
                "User-Agent": "com.google.android.youtube/19.09.37 (Linux; U; Android 9; en_US)",
                "X-Youtube-Client-Name": DirectPlaybackClient.android.clientHeaderName,
                "X-Youtube-Client-Version": DirectPlaybackClient.android.clientVersion
            ]
        }
        if let visitorData, !visitorData.isEmpty {
            headers["X-Goog-Visitor-Id"] = visitorData
        }
        return headers
    }

    private func attachPlayer(item: AVPlayerItem) {
        resetPlaybackSurfaces()

        playerSpinner.stopAnimating()
        playerStatusLabel.isHidden = true

        startObservingPlayerItem(item)

        let player = AVPlayer(playerItem: item)
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

    private func resetPlaybackSurfaces() {
        manifestPlayerView?.stop()
        manifestPlayerView?.removeFromSuperview()
        manifestPlayerView = nil

        directPlayerView?.pause()
        directPlayerView?.reset(cleanAsset: true)
        directPlayerView?.removeFromSuperview()
        directPlayerView = nil

        if let existingItem = playerViewController?.player?.currentItem {
            stopObservingPlayerItem(existingItem)
        }
        playerViewController?.player?.pause()
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil
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
    }

    private func stopObservingPlayerItem(_ item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemNewErrorLogEntry, object: item)
        item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), context: &playerItemContext)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &playerItemContext,
              keyPath == #keyPath(AVPlayerItem.status),
              let item = object as? AVPlayerItem else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        switch item.status {
        case .readyToPlay:
            print("[WatchViewController] player item ready")
        case .failed:
            print("[WatchViewController] player item failed: \(item.error?.localizedDescription ?? "unknown")")
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

extension WatchViewController: SZAVPlayerDelegate {
    func avplayer(_ avplayer: SZAVPlayer, refreshed currentTime: Float64, loadedTime: Float64, totalTime: Float64) {}

    func avplayer(_ avplayer: SZAVPlayer, didChanged status: SZAVPlayerStatus) {
        print("[WatchViewController] SZAVPlayer status: \(status)")
        switch status {
        case .readyToPlay:
            retriedDirectPlaybackWithWeb = false
            playerSpinner.stopAnimating()
            playerStatusLabel.isHidden = true
            avplayer.play()
        case .loading:
            playerSpinner.startAnimating()
            playerStatusLabel.isHidden = false
            playerStatusLabel.text = "Loading direct stream..."
        case .loadingFailed:
            if activeDirectPlaybackClient == .tvHTML5, !retriedDirectPlaybackWithWeb {
                retriedDirectPlaybackWithWeb = true
                playerStatusLabel.isHidden = false
                playerStatusLabel.textColor = ThemeManager.shared.primaryText
                playerStatusLabel.text = "TV playback blocked, retrying WEB client..."
                avplayer.pause()
                avplayer.reset(cleanAsset: true)
                startPlayback(using: .web)
                return
            }
            playerSpinner.stopAnimating()
            playerStatusLabel.isHidden = false
            playerStatusLabel.textColor = .systemRed
            playerStatusLabel.text = "Direct playback failed"
        case .bufferBegin:
            playerSpinner.startAnimating()
        case .bufferEnd:
            playerSpinner.stopAnimating()
        case .playEnd, .playbackStalled:
            break
        }
    }

    func avplayer(_ avplayer: SZAVPlayer, didReceived remoteCommand: SZAVPlayerRemoteCommand) -> Bool {
        return false
    }
}
