import UIKit

private enum ChannelTabRequest {
    static let videos = "EgZ2aWRlb3PyBgQKAjoA"
    static let live = "EgdzdHJlYW1z8gYECgJ6AA=="
}

extension ChannelViewController {
    func installTabsView() {
        guard let cv = collectionView else {
            return
        }
        tabsView.onTabSelected = { [weak self] tab in
            self?.selectTab(tab)
        }
        view.addSubview(tabsView)
        NSLayoutConstraint.activate([
            tabsView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        installFilterBar()
        applyCollectionInsets(to: cv)
    }

    func installFilterBar() {
        filterBar.isHidden = true
        filterBar.onChipSelected = { [weak self] chip in
            self?.loadVideoTab(params: chip.params)
        }
        view.addSubview(filterBar)
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: tabsView.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func selectTab(_ tab: ChannelTabsView.Tab) {
        guard tab != currentTab else {
            return
        }
        currentTab = tab
        filterBar.clearChips()
        filterBar.isHidden = true
        loadCurrentTab()
    }

    func loadCurrentTab() {
        beginTabLoad()
        switch currentTab {
        case .videos:
            loadVideoTab(params: ChannelTabRequest.videos)
        case .live:
            loadVideoTab(params: ChannelTabRequest.live)
        case .playlists:
            loadPlaylistTab()
        }
    }

    func beginTabLoad() {
        playlistLookup = [:]
        spinner.startAnimating()
        isLoadingInitial = true
        errorLabel.isHidden = true
        collectionView?.reloadData()
    }

    func loadVideoTab(params: String) {
        let expectedTab = currentTab
        ServiceContainer.channelTabs.fetchChannelTab(
            channelId: channelId,
            params: params
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    return
                }
                self?.handleSelectedTabVideos(result)
            }
        }
    }

    func loadPlaylistTab() {
        let expectedTab = currentTab
        ServiceContainer.channelTabs.fetchChannelPlaylists(
            channelId: channelId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    return
                }
                self?.handleSelectedTabPlaylists(result)
            }
        }
    }

    func handleSelectedTabVideos(
        _ result: Result<ChannelTabPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let tabPage):
            setPage(tabPage.feedPage)
            errorLabel.isHidden = !videos.isEmpty
            applyFilterChips(tabPage.filterChips)
        case .failure(let error):
            AppLog.channel("tab load failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func handleSelectedTabPlaylists(
        _ result: Result<PlaylistsPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            let feedPage = playlistFeedPage(from: page.playlists, continuation: page.continuation)
            setPage(feedPage)
            errorLabel.isHidden = !page.playlists.isEmpty
        case .failure(let error):
            AppLog.channel("playlist tab failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func applyFilterChips(_ chips: [ChannelFilterChip]) {
        guard !chips.isEmpty else {
            return
        }
        filterBar.setChips(chips, selected: 0)
        filterBar.isHidden = false
        adjustCollectionInsetsForFilterBar()
    }

    func loadMoreVideos(continuation: String) {
        let expectedTab = currentTab
        ServiceContainer.channelTabs.fetchChannelTabNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    self?.finishLoadingMore()
                    return
                }
                self?.handlePageResult(result)
            }
        }
    }

    func loadMorePlaylists(continuation: String) {
        let expectedTab = currentTab
        ServiceContainer.channelTabs.fetchChannelPlaylistsNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    self?.finishLoadingMore()
                    return
                }
                switch result {
                case .success(let page):
                    let feedPage = self?.playlistFeedPage(
                        from: page.playlists,
                        continuation: page.continuation
                    ) ?? FeedPage(videos: [], continuation: nil)
                    self?.appendPage(feedPage)
                case .failure:
                    self?.finishLoadingMore()
                }
            }
        }
    }
}
