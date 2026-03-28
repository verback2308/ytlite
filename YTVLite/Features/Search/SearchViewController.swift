import UIKit

class SearchViewController: UIViewController {
    private let service: SearchService = ServiceContainer.video
    private var results: [Video] = []
    private var lastQuery: String = ""
    private var activeSearchQuery: String?
    private var searchCancellationToken = CancellationToken()

    private let searchBar = UISearchBar()
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        setupSearchBar()
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "Search YouTube"
        searchBar.text = lastQuery.isEmpty ? nil : lastQuery
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            searchBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            searchBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            )
        ])
    }

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 220
        tableView.separatorInset = UIEdgeInsets(
            top: 0, left: 12, bottom: 0, right: 12
        )
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.addTarget(
            self,
            action: #selector(handleRefresh),
            for: .valueChanged
        )
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        activateTableConstraints()
    }

    private func activateTableConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: searchBar.bottomAnchor
            ),
            tableView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            tableView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            tableView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        searchBar.barStyle = theme.barStyle
        searchBar.backgroundColor = theme.background
        tableView.reloadData()
    }

    @objc
    private func handleRefresh() {
        guard !lastQuery.isEmpty else {
            refreshControl.endRefreshing()
            return
        }
        search(query: lastQuery)
    }

    private func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            clearSearchResults()
            return
        }

        let cancellationToken = beginSearch(for: normalizedQuery)
        service.search(
            query: normalizedQuery,
            cancellationToken: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.shouldApplyResult(
                    for: normalizedQuery,
                    cancellationToken: cancellationToken
                ) else {
                    return
                }
                self.applySearchResult(result)
            }
        }
    }

    private func beginSearch(for query: String) -> CancellationToken {
        searchCancellationToken.cancel()
        let cancellationToken = CancellationToken()
        searchCancellationToken = cancellationToken
        lastQuery = query
        activeSearchQuery = query
        return cancellationToken
    }

    private func applySearchResult(_ result: Result<[Video], Error>) {
        refreshControl.endRefreshing()
        switch result {
        case .success(let videos):
            results = videos
            tableView.reloadData()
        case .failure(let error):
            presentSearchError(error)
        }
    }

    private func presentSearchError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "OK", style: .default)
        )
        present(alert, animated: true)
    }

    private func shouldApplyResult(
        for query: String,
        cancellationToken: CancellationToken
    ) -> Bool {
        searchCancellationToken === cancellationToken
            && activeSearchQuery == query
            && !cancellationToken.isCancelled
    }

    private func clearSearchResults() {
        searchCancellationToken.cancel()
        searchCancellationToken = CancellationToken()
        activeSearchQuery = nil
        lastQuery = ""
        results = []
        refreshControl.endRefreshing()
        tableView.reloadData()
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text, !query.isEmpty else {
            return
        }
        searchBar.resignFirstResponder()
        search(query: query)
    }

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        if searchText.isEmpty {
            clearSearchResults()
        }
    }
}

extension SearchViewController: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        results.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionVideoCell.reuseId,
            for: indexPath
        ) as? SubscriptionVideoCell else {
            return UITableViewCell()
        }
        let video = results[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            guard let channelId = video.channelId else {
                return
            }
            self?.navigationController?.pushViewController(
                ChannelViewController(
                    channelId: channelId,
                    channelName: video.channelName
                ),
                animated: true
            )
        }
        return cell
    }
}

extension SearchViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        let video = results[indexPath.row]
        VideoRouter.shared.open(video: video, from: self)
    }
}
