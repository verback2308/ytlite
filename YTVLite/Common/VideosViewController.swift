import UIKit

class VideosViewController: UIViewController {

    var columns: Int { 5 }

    private(set) var videos: [Video] = []
    private(set) var collectionView: UICollectionView!
    let spinner = UIActivityIndicatorView(style: .white)

    private var continuationToken: String?
    private var isLoadingMore = false
    private var seenVideoIds: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupSpinner()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateItemSize()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)
        collectionView.dataSource = self
        collectionView.delegate = self

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(collectionView)
    }

    @objc func handleRefresh() {}

    func handleScroll(_ scrollView: UIScrollView) {}

    func openChannel(for video: Video) {
        guard let channelId = video.channelId else { return }
        navigationController?.pushViewController(ChannelViewController(channelId: channelId,
                                                                      channelName: video.channelName),
                                                 animated: true)
    }

    func endRefreshing() {
        collectionView.refreshControl?.endRefreshing()
    }

    // Override in subclasses to load next page using continuationToken
    func handleLoadMore() {}

    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
    }

    private func updateItemSize() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let inset = layout.sectionInset.left + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing * CGFloat(columns - 1)
        let width = floor((collectionView.bounds.width - inset - spacing) / CGFloat(columns))
        let height = width * (9.0 / 16.0) + 80
        let newSize = CGSize(width: width, height: height)
        if layout.itemSize != newSize {
            layout.itemSize = newSize
            layout.invalidateLayout()
        }
    }

    @objc func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        collectionView?.backgroundColor = t.background
        collectionView?.reloadData()
    }

    // Reset and show first page
    func setPage(_ page: FeedPage) {
        seenVideoIds = []
        videos = []
        appendPage(page)
    }

    // Append a page of results (deduplicates by video id)
    func appendPage(_ page: FeedPage) {
        let newVideos = page.videos.filter { seenVideoIds.insert($0.id).inserted }
        videos.append(contentsOf: newVideos)
        continuationToken = page.continuation
        isLoadingMore = false
        collectionView.reloadData()
    }

    func finishLoadingMore() {
        isLoadingMore = false
    }

    var currentContinuation: String? { continuationToken }
}

extension VideosViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        videos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseId, for: indexPath) as! VideoCell
        let video = videos[indexPath.item]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            self?.openChannel(for: video)
        }
        return cell
    }
}

extension VideosViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let videoId = videos[indexPath.item].id
        navigationController?.pushViewController(PlayerViewController(videoId: videoId), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard !isLoadingMore, continuationToken != nil, indexPath.item >= videos.count - 4 else { return }
        isLoadingMore = true
        handleLoadMore()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleScroll(scrollView)
    }
}
