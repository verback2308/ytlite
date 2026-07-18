import UIKit

// MARK: - Channel Filter Bar

extension SubscriptionsViewController {
    func setupChannelBar() {
        channelBar.onChannelTapped = { [weak self] channel in
            self?.handleChannelTap(channel)
        }
        channelBar.onAllTapped = { [weak self] in
            self?.openAllChannels()
        }
    }

    func updateChannelBarFrame() {
        guard tableView.tableHeaderView === channelBar else {
            return
        }
        let width = tableView.bounds.width
        if channelBar.frame.width != width {
            channelBar.frame = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: ChannelAvatarBarView.preferredHeight
            )
            tableView.tableHeaderView = channelBar
        }
    }

    func handleChannelTap(_ channel: SubscribedChannel) {
        if selectedChannel?.id == channel.id {
            exitChannelFilter()
        } else {
            enterChannelFilter(channel)
        }
    }

    func openAllChannels() {
        let list = SubscribedChannelsViewController(
            channels: subscribedChannels,
            channelViewControllerFactory: channelViewControllerFactory
        )
        navigationController?.pushViewController(list, animated: true)
    }

    @objc
    func exitChannelFilterTapped() {
        exitChannelFilter()
    }

    func exitChannelFilter() {
        guard selectedChannel != nil else {
            return
        }
        selectedChannel = nil
        channelBar.setSelectedChannelId(nil)
        title = "订阅"
        navigationItem.leftBarButtonItem = nil
        videos = stashedVideos
        continuationToken = stashedContinuation
        seenVideoIds = stashedSeenVideoIds
        stashedVideos = []
        stashedContinuation = nil
        stashedSeenVideoIds = []
        isLoadingInitial = false
        isLoadingMore = false
        tableView.reloadData()
    }
}

// MARK: - Private Helpers

private extension SubscriptionsViewController {
    func enterChannelFilter(_ channel: SubscribedChannel) {
        if selectedChannel == nil {
            stashedVideos = videos
            stashedContinuation = continuationToken
            stashedSeenVideoIds = seenVideoIds
        }
        selectedChannel = channel
        channelBar.setSelectedChannelId(channel.id)
        title = channel.title
        installBackButton()
        isLoadingInitial = true
        isLoadingMore = false
        videos = []
        continuationToken = nil
        tableView.reloadData()
        loadChannelVideos(channel)
    }

    func installBackButton() {
        guard navigationItem.leftBarButtonItem == nil else {
            return
        }
        navigationItem.leftBarButtonItem = NavChevron.barButton(
            kind: .back,
            target: self,
            action: #selector(exitChannelFilterTapped)
        )
    }
}

// MARK: - Channel-scoped Feed Loading

extension SubscriptionsViewController {
    func loadChannelVideos(_ channel: SubscribedChannel) {
        let expectedId = channel.id
        channelTabsService.fetchChannelTab(
            channelId: channel.id,
            params: ChannelTabParams.videos
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.selectedChannel?.id == expectedId
                else { return }
                self.handleChannelVideosResult(result)
            }
        }
    }

    func loadMoreChannelVideos(
        continuation: String,
        channelId: String
    ) {
        channelTabsService.fetchChannelTabNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.selectedChannel?.id == channelId
                else {
                    self?.finishLoadingMore()
                    return
                }
                switch result {
                case .success(let page):
                    self.appendPage(
                        self.enrichedWithSelectedChannel(page)
                    )
                case .failure(let error):
                    self.finishLoadingMore()
                    AppLog.subs("channel pagination error: \(error)")
                }
            }
        }
    }

    private func handleChannelVideosResult(
        _ result: Result<ChannelTabPage, Error>
    ) {
        spinner.stopAnimating()
        tableView.refreshControl?.endRefreshing()
        switch result {
        case .success(let tabPage):
            setPage(enrichedWithSelectedChannel(tabPage.feedPage))
        case .failure(let error):
            AppLog.subs("channel filter load failed: \(error)")
            isLoadingInitial = false
            videos = []
            continuationToken = nil
            tableView.reloadData()
        }
    }

    /// Channel-tab videos often omit owner metadata; fill it in
    /// from the selected channel so cells render name and avatar.
    private func enrichedWithSelectedChannel(
        _ page: FeedPage
    ) -> FeedPage {
        guard let channel = selectedChannel else {
            return page
        }
        let videos = page.videos.map { video -> Video in
            var copy = video
            if copy.channelId == nil {
                copy.channelId = channel.id
            }
            if copy.channelName.isEmpty {
                copy.channelName = channel.title
            }
            if copy.channelAvatarURL == nil {
                copy.channelAvatarURL = channel.avatarURL
            }
            return copy
        }
        return FeedPage(videos: videos, continuation: page.continuation)
    }
}
