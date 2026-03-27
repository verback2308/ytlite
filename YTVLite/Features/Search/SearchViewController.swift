import UIKit

class SearchViewController: UIViewController {

    private let service: SearchService = ServiceContainer.video
    private var results: [Video] = []
    private var lastQuery: String = ""

    private let searchBar = UISearchBar()
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        setupSearchBar()
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "Search YouTube"
        searchBar.text = lastQuery.isEmpty ? nil : lastQuery
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupTableView() {
        tableView.register(SubscriptionVideoCell.self,
                           forCellReuseIdentifier: SubscriptionVideoCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 220
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        searchBar.barStyle = t.barStyle
        searchBar.backgroundColor = t.background
        tableView.reloadData()
    }

    @objc private func handleRefresh() {
        guard !lastQuery.isEmpty else {
            refreshControl.endRefreshing()
            return
        }
        search(query: lastQuery)
    }

    private func search(query: String) {
        lastQuery = query
        service.search(query: query) { [weak self] result in
            DispatchQueue.main.async {
                self?.refreshControl.endRefreshing()
                switch result {
                case .success(let videos):
                    self?.results = videos
                    self?.tableView.reloadData()
                case .failure(let error):
                    let alert = UIAlertController(title: "Error",
                                                  message: error.localizedDescription,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text, !query.isEmpty else { return }
        searchBar.resignFirstResponder()
        search(query: query)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            lastQuery = ""
            results = []
            tableView.reloadData()
        }
    }
}

extension SearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionVideoCell.reuseId,
                                                 for: indexPath) as! SubscriptionVideoCell
        let video = results[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            guard let channelId = video.channelId else { return }
            self?.navigationController?.pushViewController(
                ChannelViewController(channelId: channelId, channelName: video.channelName),
                animated: true)
        }
        return cell
    }
}

extension SearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let video = results[indexPath.row]
        VideoRouter.shared.open(video: video, from: self)
    }
}
