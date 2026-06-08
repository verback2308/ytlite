import UIKit

class VideosViewController: UIViewController {
    // MARK: - Type Properties

    private static let skeletonCount = 9

    // MARK: - Instance Properties

    var columns: Int { 5 }

    private(set) var videos: [Video] = []
    private(set) var collectionView: UICollectionView?
    let channelViewControllerFactory: (String, String) -> ChannelViewController
    let videoRouter: VideoRouter
    let spinner = UIActivityIndicatorView(style: .white)
    var isLoadingInitial = true

    private var continuationToken: String?
    private var isLoadingMore = false
    private var seenVideoIds: Set<String> = []

    var currentContinuation: String? { continuationToken }

    init(
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> ChannelViewController,
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
        cv.register(
            VideoCell.self,
            forCellWithReuseIdentifier: VideoCell.reuseId
        )
        cv.dataSource = self
        cv.delegate = self

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

    @objc
    func handleRefresh() {}

    func handleScroll(_ scrollView: UIScrollView) {}

    func openChannel(for video: Video) {
        guard let channelId = video.channelId else {
            return
        }
        navigationController?.pushViewController(
            channelViewControllerFactory(
                channelId,
                video.channelName
            ),
            animated: true
        )
    }

    func openVideo(_ video: Video) {
        videoRouter.open(
            video: video,
            from: self
        )
    }

    func endRefreshing() {
        collectionView?.refreshControl?.endRefreshing()
    }

    // Override in subclasses to load next page
    func handleLoadMore() {}

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

    func updateItemSize() {
        guard let collectionView,
              let layout = collectionView
                  .collectionViewLayout
                  as? UICollectionViewFlowLayout
        else {
            return
        }
        let inset = layout.sectionInset.left
            + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing
            * CGFloat(max(columns - 1, 0))
        let available = collectionView.bounds.width
            - inset - spacing
        let width = floor(available / CGFloat(columns))
        let height: CGFloat = width * (9.0 / 16.0) + 92
        let newSize = CGSize(
            width: width,
            height: height
        )
        if layout.itemSize != newSize {
            layout.itemSize = newSize
            layout.invalidateLayout()
        }
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        collectionView?.backgroundColor = theme.background
        collectionView?.reloadData()
    }

    func setPage(_ page: FeedPage) {
        isLoadingInitial = false
        seenVideoIds = []
        videos = []
        let newVideos = page.videos.filter {
            seenVideoIds.insert($0.id).inserted
        }
        videos.append(contentsOf: newVideos)
        continuationToken = page.continuation
        isLoadingMore = false
        collectionView?.reloadData()
    }

    func appendPage(_ page: FeedPage) {
        let newVideos = page.videos.filter {
            seenVideoIds.insert($0.id).inserted
        }
        let insertStart = videos.count
        videos.append(contentsOf: newVideos)
        continuationToken = page.continuation
        isLoadingMore = false

        if isLoadingInitial {
            isLoadingInitial = false
            collectionView?.reloadData()
        } else {
            let indexPaths =
                (insertStart..<videos.count).map {
                    IndexPath(item: $0, section: 0)
                }
            collectionView?.insertItems(at: indexPaths)
        }
    }

    func finishLoadingMore() {
        isLoadingMore = false
    }
}

extension VideosViewController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        isLoadingInitial
            ? VideosViewController.skeletonCount
            : videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView
            .dequeueReusableCell(
                withReuseIdentifier: VideoCell.reuseId,
                for: indexPath
            ) as? VideoCell
        else {
            return UICollectionViewCell()
        }
        cell.forceGridLayout = true
        if isLoadingInitial {
            cell.configureSkeleton()
            return cell
        }
        let video = videos[indexPath.item]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            self?.openChannel(for: video)
        }
        return cell
    }
}

extension VideosViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard !isLoadingInitial else {
            return
        }
        openVideo(videos[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard !isLoadingMore,
              continuationToken != nil,
              indexPath.item >= videos.count - 4
        else {
            return
        }
        isLoadingMore = true
        handleLoadMore()
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        handleScroll(scrollView)
    }
}
