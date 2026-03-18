import UIKit

class HomeViewController: VideosViewController {

    private let ytAPI = YouTubeAPIClient()
    override var columns: Int { 3 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        setupThemeButton()
        loadFeed()
    }

    private func setupThemeButton() {
        let btn = UIBarButtonItem(title: ThemeManager.shared.isDark ? "☀" : "☾",
                                  style: .plain, target: self, action: #selector(toggleTheme))
        navigationItem.rightBarButtonItem = btn
    }

    @objc private func toggleTheme() {
        ThemeManager.shared.isDark.toggle()
        navigationItem.rightBarButtonItem?.title = ThemeManager.shared.isDark ? "☀" : "☾"
    }

    override func applyTheme() {
        super.applyTheme()
        navigationItem.rightBarButtonItem?.title = ThemeManager.shared.isDark ? "☀" : "☾"
    }

    private func loadFeed() {
        ytAPI.fetchPopularVideos { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                switch result {
                case .success(let videos): self?.setVideos(videos)
                case .failure(let error): print("Home feed error: \(error)")
                }
            }
        }
    }
}
