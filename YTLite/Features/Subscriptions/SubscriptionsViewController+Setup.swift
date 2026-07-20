import UIKit

// MARK: - Setup

extension SubscriptionsViewController {
    func loadInitialContent() {
        if OAuthClient.shared.isAnonymous {
            AppLog.subs("anonymous → skip load")
            spinner.stopAnimating()
            showSignInPrompt(true)
            return
        }
        loadSubscribedChannels()
        cache.loadSubscriptionsFeed { [weak self] cachedPage in
            self?.handleCachedSubscriptions(cachedPage)
        }
    }

    func setupSignInPrompt() {
        let prompt = SignInEmptyStateView(
            message: "登录以查看您的订阅"
        )
        prompt.isHidden = true
        prompt.onSignIn = { [weak self] in
            self?.toolbarOpenProfile()
        }
        view.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            prompt.centerYAnchor.constraint(
                equalTo: view.centerYAnchor,
                constant: -40
            ),
            prompt.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 40
            ),
            prompt.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -40
            )
        ])
        signInPrompt = prompt
    }

    func showSignInPrompt(_ show: Bool) {
        signInPrompt?.isHidden = !show
        tableView.isHidden = show
    }

    func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier:
                SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight =
            UITableView.automaticDimension
        tableView.estimatedRowHeight = 220
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints =
            false
        let refresh = UIRefreshControl()
        refresh.addTarget(
            self,
            action: #selector(handleRefresh),
            for: .valueChanged
        )
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        pinToEdges(tableView, of: view)
    }

    func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints =
            false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            spinner.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            )
        ])
        spinner.startAnimating()
    }
}

// MARK: - Data Loading

extension SubscriptionsViewController {
    func loadFeed() {
        let t0 = Date()
        AppLog.subs("network fetch start")
        service.fetchSubscriptionFeed { [weak self] result in
            self?.handleFeedResult(result, since: t0)
        }
    }

    func loadMore() {
        guard let continuation = continuationToken else {
            finishLoadingMore()
            return
        }
        if let channel = selectedChannel {
            loadMoreChannelVideos(
                continuation: continuation,
                channelId: channel.id
            )
            return
        }
        service.fetchSubscriptionsNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.selectedChannel == nil else {
                    self?.finishLoadingMore()
                    return
                }
                switch result {
                case let .success(page):
                    self.appendPage(page)
                case let .failure(error):
                    self.finishLoadingMore()
                    AppLog.subs("pagination error: \(error)")
                }
            }
        }
    }

    func setPage(_ page: FeedPage) {
        isLoadingInitial = false
        seenVideoIds = []
        sortDatesByVideoId = [:]
        videos = []
        appendPage(page)
    }

    func appendPage(_ page: FeedPage) {
        let newVideos = page.videos.filter {
            seenVideoIds.insert($0.id).inserted
        }
        if !newVideos.isEmpty {
            videos.append(contentsOf: newVideos)
        }
        continuationToken = page.continuation
        isLoadingMore = false
        tableView.reloadData()
    }

    func finishLoadingMore() {
        isLoadingMore = false
    }
}

// MARK: - Private Helpers

private extension SubscriptionsViewController {
    func handleCachedSubscriptions(
        _ cachedPage: FeedPage?,
        firstVisit: Bool = true
    ) {
        guard selectedChannel == nil else {
            return
        }
        if let cachedPage {
            AppLog.subs(
                "cache-hit → showing "
                    + "\(cachedPage.videos.count)"
                    + " videos"
            )
            isLoadingInitial = false
            spinner.stopAnimating()
            setPage(cachedPage)
            harvestChannels(from: cachedPage)
        } else {
            AppLog.subs("no cache → network")
            loadFeed()
        }
    }

    func handleFeedResult(
        _ result: Result<FeedPage, Error>,
        since t0: Date
    ) {
        DispatchQueue.main.async {
            let ms = Int(
                Date().timeIntervalSince(t0) * 1_000
            )
            self.spinner.stopAnimating()
            self.tableView.refreshControl?
                .endRefreshing()
            switch result {
            case let .success(page):
                AppLog.subs(
                    "network done \(ms)ms"
                        + " videos=\(page.videos.count)"
                )
                self.applyFeedPage(page)
            case let .failure(error):
                AppLog.subs(
                    "network failed \(ms)ms: \(error)"
                )
                self.finishLoadingMore()
                if case APIError.unauthorized = error {
                    self.isLoadingInitial = false
                    self.showSignInPrompt(true)
                    self.tableView.reloadData()
                }
            }
        }
    }

    func applyFeedPage(_ page: FeedPage) {
        showSignInPrompt(false)
        cache.setSubscriptionsFeed(page)
        if selectedChannel == nil {
            setPage(page)
        } else {
            stashedVideos = page.videos
            stashedContinuation = page.continuation
            stashedSeenVideoIds = Set(page.videos.map { $0.id })
        }
        harvestChannels(from: page)
    }

    func pinToEdges(
        _ child: UIView, of parent: UIView
    ) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(
                equalTo: parent.topAnchor
            ),
            child.leadingAnchor.constraint(
                equalTo: parent.leadingAnchor
            ),
            child.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor
            ),
            child.bottomAnchor.constraint(
                equalTo: parent.bottomAnchor
            )
        ])
    }
}
