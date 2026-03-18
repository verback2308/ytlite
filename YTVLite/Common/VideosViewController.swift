import UIKit

class VideosViewController: UIViewController {

    var columns: Int { 5 }

    private(set) var videos: [Video] = []
    private(set) var collectionView: UICollectionView!
    let spinner = UIActivityIndicatorView(style: .white)

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
        view.addSubview(collectionView)
    }

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
        let height = width * (9.0 / 16.0) + 62
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

    func setVideos(_ videos: [Video]) {
        self.videos = videos
        collectionView.reloadData()
    }
}

extension VideosViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        videos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseId, for: indexPath) as! VideoCell
        cell.configure(with: videos[indexPath.item])
        return cell
    }
}

extension VideosViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let videoId = videos[indexPath.item].id
        navigationController?.pushViewController(PlayerViewController(videoId: videoId), animated: true)
    }
}
