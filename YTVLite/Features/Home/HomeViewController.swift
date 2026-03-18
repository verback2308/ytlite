import UIKit

class HomeViewController: VideosViewController {

    private let service = ServiceContainer.video
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
        errorLabel.isHidden = true
        service.fetchHomeFeed { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.endRefreshing()
                switch result {
                case .success(let page):
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
