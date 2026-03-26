import UIKit

class HomeViewController: VideosViewController {

    private let service = ServiceContainer.video
    private let cache = AppCache.shared
    override var columns: Int {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 1
        }
        let w = view.bounds.width
        if w < 500 { return 1 }
        return w > view.bounds.height ? 3 : 2
    }

    private lazy var errorLabel: UILabel = {
        let l = UILabel()
        l.text = "Couldn't load feed\nPull down to retry"
        l.textColor = .lightGray
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = UIFont.systemFont(ofSize: 15)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private lazy var signInEmptyView: SignInEmptyStateView = {
        let v = SignInEmptyStateView(message: "Sign in to see your recommendations")
        v.isHidden = true
        v.onSignIn = { [weak self] in self?.toolbarOpenProfile() }
        return v
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        AppLog.home("viewDidLoad")
        view.addSubview(errorLabel)
        view.addSubview(signInEmptyView)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            signInEmptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInEmptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            signInEmptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            signInEmptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
        setupToolbar()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSignOut),
                                               name: .userDidSignOut, object: nil)

        if let cachedPage = cache.cachedHomeFeed() {
            AppLog.home("cache-hit → showing \(cachedPage.videos.count) videos instantly")
            isLoadingInitial = false
            spinner.stopAnimating()
            setPage(cachedPage)
        } else {
            AppLog.home("no cache → loading from network")
            loadFeed()
        }
    }

    private func setupToolbar() {
        ToolbarManager.shared.install(in: self)
    }

    @objc private func handleSignOut() {
        cache.clearHomeFeed()
        setPage(FeedPage(videos: [], continuation: nil))
        toolbarRefreshProfileButton()
        loadFeed()
    }

    override func handleRefresh() {
        cache.clearHomeFeed()
        loadFeed()
    }

    private func loadFeed() {
        let t0 = Date()
        AppLog.home("network fetch start")
        errorLabel.isHidden = true
        signInEmptyView.isHidden = true
        service.fetchHomeFeed { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                self.spinner.stopAnimating()
                self.endRefreshing()
                switch result {
                case .success(let page):
                    AppLog.home("network fetch done \(ms)ms videos=\(page.videos.count)")
                    self.cache.setHomeFeed(page)
                    self.setPage(page)
                case .failure(let err):
                    AppLog.home("network fetch failed \(ms)ms: \(err)")
                    self.setPage(FeedPage(videos: [], continuation: nil))
                    if OAuthClient.shared.isAnonymous {
                        self.signInEmptyView.isHidden = false
                    } else {
                        self.errorLabel.isHidden = false
                    }
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
