import UIKit

class HomeViewController: VideosViewController {

    private let ytAPI = YouTubeAPIClient()
    override var columns: Int { 3 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        setupSearchButton()
        loadFeed()
    }

    private func setupSearchButton() {
        let btn = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(openSearch))
        navigationItem.rightBarButtonItem = btn
    }

    @objc private func openSearch() {
        navigationController?.pushViewController(SearchViewController(), animated: true)
    }

    override func handleRefresh() {
        loadFeed()
    }

    private func loadFeed() {
        ytAPI.fetchPopularVideos { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.endRefreshing()
                switch result {
                case .success(let videos): self?.setVideos(videos)
                case .failure(let error): print("Home feed error: \(error)")
                }
            }
        }
    }
}
