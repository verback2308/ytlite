import UIKit

class SubscriptionsViewController: UIViewController {

    private let ytAPI = YouTubeAPIClient()
    private var videos: [Video] = []
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Subscriptions"
        setupTableView()
        setupSpinner()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        loadFeed()
    }

    private func setupTableView() {
        tableView.register(SubscriptionVideoCell.self, forCellReuseIdentifier: SubscriptionVideoCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 128
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        tableView.reloadData()
    }

    private func loadFeed() {
        ytAPI.fetchSubscriptionFeed { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                switch result {
                case .success(let videos):
                    self?.videos = videos
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("Subscriptions error: \(error)")
                }
            }
        }
    }
}

extension SubscriptionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionVideoCell.reuseId, for: indexPath) as! SubscriptionVideoCell
        cell.configure(with: videos[indexPath.row])
        return cell
    }
}

extension SubscriptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let videoId = videos[indexPath.row].id
        navigationController?.pushViewController(PlayerViewController(videoId: videoId), animated: true)
    }
}
