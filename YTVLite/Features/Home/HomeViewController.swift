import UIKit

class HomeViewController: VideosViewController {

    private let service = ServiceContainer.video
    private let cache = AppCache.shared
    override var columns: Int { 3 }

    private lazy var errorLabel: UILabel = {
        let l = UILabel()
        l.text = "Feed unavailable\nRestart the mock server and re-authorize"
        l.textColor = .lightGray
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = UIFont.systemFont(ofSize: 15)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
        setupToolbar()

        if let cachedPage = cache.cachedHomeFeed() {
            isLoadingInitial = false
            spinner.stopAnimating()
            setPage(cachedPage)
        } else {
            loadFeed()
        }
    }

    private func setupToolbar() {
        // Search button on the left side of right buttons
        let searchBtn = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(openSearch))
        // Install profile + settings, then insert search before them
        ToolbarManager.shared.install(in: self)
        var items = navigationItem.rightBarButtonItems ?? []
        items.append(searchBtn)
        navigationItem.rightBarButtonItems = items
    }

    @objc private func openSearch() {
        navigationController?.pushViewController(SearchViewController(), animated: true)
    }

    override func handleRefresh() {
        cache.clearHomeFeed()
        loadFeed()
    }

    private func loadFeed() {
        errorLabel.isHidden = true
        service.fetchHomeFeed { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.endRefreshing()
                switch result {
                case .success(let page):
                    self?.cache.setHomeFeed(page)
                    self?.setPage(page)
                case .failure:
                    self?.finishLoadingMore()
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }

    override func handleLoadMore() {
        guard let continuation = currentContinuation else {
            finishLoadingMore()
            return
        }

        service.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.appendPage(page)
                case .failure:
                    self?.finishLoadingMore()
                }
            }
        }
    }
}
