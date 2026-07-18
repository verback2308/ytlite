import UIKit

/// A titled group of videos rendered as one collection-view section.
struct VideoSection {
    let title: String?
    var videos: [Video]
    /// The shelf's own token — rails page horizontally with it.
    var continuation: String?
}

class VideosViewController: UIViewController {
    // MARK: - Type Properties

    static let skeletonCount = 9

    // MARK: - Instance Properties

    var columns: Int { 5 }

    /// Whether pages' shelf partitions render as titled sections.
    /// Pages without shelf info look the same either way.
    var groupsByShelf: Bool { true }

    var useRails: Bool { false }

    private(set) var sections: [VideoSection] = []
    private(set) var collectionView: UICollectionView?
    let channelViewControllerFactory: (String, String) -> UIViewController
    let videoRouter: VideoRouter
    let spinner = UIActivityIndicatorView(style: .white)
    var isLoadingInitial = true
    var isLoadingMore = false

    private var continuationToken: String?
    private var seenVideoIds: Set<String> = []
    /// Sections with an in-flight horizontal (rail) page fetch.
    var loadingRailSections: Set<Int> = []

    var currentContinuation: String? { continuationToken }
    var videoCount: Int { sections.reduce(0) { $0 + $1.videos.count } }

    init(
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupSpinner()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateItemSize()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateItemSize()
            self?.collectionView?
                .collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Methods

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(
            top: 12, left: 8, bottom: 12, right: 8
        )

        let cv = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: layout
        )
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        registerViews(in: cv)
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self

        let refresh = UIRefreshControl()
        refresh.addTarget(
            self,
            action: #selector(handleRefresh),
            for: .valueChanged
        )
        cv.refreshControl = refresh

        view.addSubview(cv)
        collectionView = cv
    }

    private func registerViews(in cv: UICollectionView) {
        cv.register(
            VideoCell.self,
            forCellWithReuseIdentifier: VideoCell.reuseId
        )
        cv.register(
            VideoSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: VideoSectionHeaderView.reuseId
        )
        cv.register(
            ShelfRailCell.self,
            forCellWithReuseIdentifier: ShelfRailCell.reuseId
        )
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

    @objc
    func handleRefresh() {}

    func handleScroll(_ scrollView: UIScrollView) {}

    // Override in subclasses to load next page
    func handleLoadMore() {}

    /// Override in subclasses to fetch a rail's horizontal page.
    /// Must call `completion` (on the main thread) exactly once.
    func loadRailPage(
        token: String,
        completion: @escaping (FeedPage?) -> Void
    ) {
        completion(nil)
    }

    // Kept in the class body (not the extension) so subclasses can
    // override it.
    func openVideo(_ video: Video) {
        videoRouter.open(
            video: video,
            from: self
        )
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        collectionView?.backgroundColor = theme.background
    }
}

// MARK: - Page Management

extension VideosViewController {
    /// Splits the page's videos into sections following its shelf
    /// partition, deduplicating against already-shown videos.
    private func makeSections(from page: FeedPage) -> [VideoSection] {
        let grouped = groupsByShelf ? page.shelves : nil
        let shelves = grouped
            ?? [FeedShelf(title: nil, count: page.videos.count)]
        var result: [VideoSection] = []
        var index = 0
        for shelf in shelves {
            let end = min(index + shelf.count, page.videos.count)
            let slice = page.videos[index..<end].filter {
                seenVideoIds.insert($0.id).inserted
            }
            index = end
            if !slice.isEmpty {
                result.append(VideoSection(
                    title: shelf.title,
                    videos: slice,
                    continuation: shelf.continuation
                ))
            }
        }
        let rest = page.videos.dropFirst(index).filter {
            seenVideoIds.insert($0.id).inserted
        }
        if !rest.isEmpty {
            result.append(VideoSection(title: nil, videos: rest))
        }
        return result
    }

    func setPage(_ page: FeedPage) {
        isLoadingInitial = false
        seenVideoIds = []
        loadingRailSections = []
        sections = makeSections(from: page)
        continuationToken = page.continuation
        isLoadingMore = false
        collectionView?.reloadData()
    }

    /// Appends a rail's horizontal page to its section; returns the
    /// deduplicated videos that were actually added.
    func appendToRail(
        _ videos: [Video],
        section: Int,
        continuation: String?
    ) -> [Video] {
        sections[section].continuation = continuation
        let fresh = videos.filter {
            seenVideoIds.insert($0.id).inserted
        }
        sections[section].videos.append(contentsOf: fresh)
        return fresh
    }

    func appendPage(_ page: FeedPage) {
        var newSections = makeSections(from: page)
        continuationToken = page.continuation
        isLoadingMore = false

        if isLoadingInitial {
            isLoadingInitial = false
            sections.append(contentsOf: newSections)
            collectionView?.reloadData()
            return
        }
        let itemPaths = mergeIntoLastSection(&newSections)
        let insertStart = sections.count
        sections.append(contentsOf: newSections)
        collectionView?.performBatchUpdates {
            if !itemPaths.isEmpty {
                collectionView?.insertItems(at: itemPaths)
            }
            if insertStart < sections.count {
                collectionView?.insertSections(
                    IndexSet(insertStart..<sections.count)
                )
            }
        }
    }

    /// A flow-layout section always starts a new row, so a page
    /// boundary inside the same (or untitled) shelf would leave a
    /// gap — extend the previous section instead. Rails render one
    /// item per section, so item inserts don't apply there.
    private func mergeIntoLastSection(
        _ newSections: inout [VideoSection]
    ) -> [IndexPath] {
        guard !useRails,
              let first = newSections.first,
              let last = sections.indices.last,
              sections[last].title == first.title
        else {
            return []
        }
        let start = sections[last].videos.count
        sections[last].videos.append(contentsOf: first.videos)
        newSections.removeFirst()
        return (start..<start + first.videos.count).map {
            IndexPath(item: $0, section: last)
        }
    }

    func finishLoadingMore() {
        isLoadingMore = false
    }
}
