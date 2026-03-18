import UIKit

class HomeViewController: UIViewController {

    private let ytAPI = YouTubeAPIClient()
    private var videos: [Video] = []
    private var collectionView: UICollectionView!
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        view.backgroundColor = .black
        setupCollectionView()
        setupSpinner()
        loadFeed()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 1
        let width = view.bounds.width / 2 - 1
        let height = width * (9.0/16.0) + 80
        layout.itemSize = CGSize(width: width, height: height)
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
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

    private func loadFeed() {
        ytAPI.fetchPopularVideos { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                switch result {
                case .success(let videos):
                    self?.videos = videos
                    self?.collectionView.reloadData()
                case .failure(let error):
                    print("Home feed error: \(error)")
                }
            }
        }
    }
}

extension HomeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        videos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseId, for: indexPath) as! VideoCell
        cell.configure(with: videos[indexPath.item])
        return cell
    }
}

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let videoId = videos[indexPath.item].id
        navigationController?.pushViewController(PlayerViewController(videoId: videoId), animated: true)
    }
}
