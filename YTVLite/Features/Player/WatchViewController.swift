import UIKit
import AVKit

private func makePortraitRelatedLayout() -> UICollectionViewFlowLayout {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 12
    layout.minimumInteritemSpacing = 8
    layout.sectionInset = UIEdgeInsets(
        top: 0,
        left: 12,
        bottom: 16,
        right: 12
    )
    return layout
}

private func makeLandscapeRelatedLayout() -> UICollectionViewFlowLayout {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 12
    layout.minimumInteritemSpacing = 0
    layout.sectionInset = UIEdgeInsets(
        top: 0,
        left: 8,
        bottom: 12,
        right: 8
    )
    return layout
}

final class WatchViewController: UIViewController {
    // MARK: - Dependencies

    var initialVideo: Video
    let client: WatchService
    let engagementClient: EngagementService
    let channelInfoStore: ChannelInfoStore
    let channelViewControllerFactory: (
        String,
        String
    ) -> ChannelViewController
    let videoRouter: VideoRouter
    let cache = AppCache.shared

    // MARK: - State

    var watchPage: WatchPage?
    var isSubscribed: Bool = false
    var allRelatedVideos: [Video] = []
    var visibleRelatedVideos: [Video] = []
    let relatedBatchSize = 5
    var comments: [Comment] = []
    var commentsContinuation: String?
    var visibleCommentsCount = 10
    let commentsPageSize = 10
    var videoPlayerView: VideoPlayerView?
    var statusObservation: NSKeyValueObservation?
    var descriptionExpanded = false
    var isLoadingComments = false
    let sponsorBlock = SponsorBlockController()
    var autoplayOverlay: AutoplayOverlayView?
    let playbackFacade = PlaybackFacade()
    var pageLoadToken = CancellationToken()
    var isOuterScrollViewDragging = false
    var didSeekToSavedPosition = false

    // MARK: - UI Elements

    let scrollView = UIScrollView()
    let contentView = UIView()
    let relatedCollectionView: UICollectionView
    let sidebarContainer = UIView()
    let portraitRelatedLayout: UICollectionViewFlowLayout
    let landscapeRelatedLayout: UICollectionViewFlowLayout
    let playerContainer = UIView()
    let playerSpinner = UIActivityIndicatorView(
        style: .whiteLarge
    )
    let playerStatusLabel = UILabel()
    let titleLabel = UILabel()
    let metaLabel = UILabel()
    let channelAvatarView = ThumbnailImageView(
        frame: .zero
    )
    let channelNameLabel = UILabel()
    let channelMetaLabel = UILabel()
    let subscribeButton = UIButton(type: .system)
    let descriptionLabel = UILabel()
    let descriptionButton = UIButton(type: .system)
    let commentsLabel = UILabel()
    let commentsStackView = UIStackView()
    let loadMoreCommentsButton = UIButton(
        type: .system
    )
    let actionBar = UIStackView()
    let likeButton = UIButton(type: .system)
    let dislikeButton = UIButton(type: .system)
    let shareButton = UIButton(type: .system)
    let saveButton = UIButton(type: .system)
    let downloadButton = UIButton(type: .system)
    let likeCountLabel = UILabel()
    let dislikeCountLabel = UILabel()
    var likeCount: String?; var dislikeCount: String?
    var currentLikeStatus: LikeStatus = .indifferent

    // MARK: - Constraints

    var playerAspectConstraint: NSLayoutConstraint?
    var relatedHeightConstraint: NSLayoutConstraint?
    var playerTopConstraint: NSLayoutConstraint?
    var playerLeadingConstraint: NSLayoutConstraint?
    var playerTrailingConstraint: NSLayoutConstraint?
    var playerToSidebarConstraint: NSLayoutConstraint?
    var scrollTopToPlayerConstraint: NSLayoutConstraint?
    var scrollTrailingConstraint: NSLayoutConstraint?
    var scrollToSidebarConstraint: NSLayoutConstraint?
    var sidebarTopConstraint, sidebarTrailingConstraint: NSLayoutConstraint?
    var sidebarBottomConstraint, sidebarWidthConstraint: NSLayoutConstraint?
    var bottomCommentsConstraint: NSLayoutConstraint?
    var relatedPortraitConstraints: [NSLayoutConstraint] = []
    var relatedLandscapeConstraints: [NSLayoutConstraint] = []
    var isShowingLandscapeRelated = false
    var fullscreenSnapshot: (
        superview: UIView,
        frame: CGRect
    )?
    var channelTopToMeta: NSLayoutConstraint?
    var channelTopToDesc: NSLayoutConstraint?

    // MARK: - Computed Properties

    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations:
        UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    // MARK: - Initializers

    init(
        video: Video,
        watchService: WatchService,
        engagementService: EngagementService,
        channelInfoStore: ChannelInfoStore,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
        videoRouter: VideoRouter = .shared
    ) {
        let portraitLayout = makePortraitRelatedLayout()
        self.portraitRelatedLayout = portraitLayout

        let landscapeLayout = makeLandscapeRelatedLayout()
        self.landscapeRelatedLayout = landscapeLayout

        self.relatedCollectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: portraitLayout
        )
        self.initialVideo = video
        self.client = watchService
        self.engagementClient = engagementService
        self.channelInfoStore = channelInfoStore
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
        playbackFacade.context = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        applyTheme()
        setupNavigationBar()
        loadInitialState()
        let id = initialVideo.id
        if let cached = cache.cachedWatchPage(
            videoId: id
        ) {
            applyWatchPage(cached)
        }
        loadWatchPage()
        addNotificationObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutForSize()
    }

    override func viewWillDisappear(
        _ animated: Bool
    ) {
        super.viewWillDisappear(animated)
        let isDismissing = isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true
        if isDismissing {
            pageLoadToken.cancel()
            videoPlayerView?.player?.pause()
        }
    }

    // MARK: - Other Methods

    override func viewWillTransition(
        to size: CGSize,
        with coordinator:
            UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(
            to: size,
            with: coordinator
        )
        coordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.updateLayoutForSize(size)
                self?.view.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                self?.updateLayoutForSize()
            }
        )
    }

    // MARK: - Deinitializer

    deinit {
        NotificationCenter.default
            .removeObserver(self)
        statusObservation?.invalidate()
        statusObservation = nil
        if let item =
            videoPlayerView?.player?.currentItem {
            stopObservingPlayerItem(item)
        }
        videoPlayerView?.detach()
        playbackFacade.reset()
    }
}
