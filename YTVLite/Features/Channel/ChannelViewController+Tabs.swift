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
        applyCollectionInsets(to: cv)
    }

    func selectTab(_ tab: ChannelTabsView.Tab) {
        guard tab != currentTab else {
            return
        }
        currentTab = tab
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
        _ result: Result<FeedPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            setPage(page)
            errorLabel.isHidden = !videos.isEmpty
        case .failure(let error):
            AppLog.channel("tab load failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func handleSelectedTabPlaylists(
        _ result: Result<[Playlist], Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let playlists):
            let page = playlistFeedPage(from: playlists)
            setPage(page)
            errorLabel.isHidden = !playlists.isEmpty
        case .failure(let error):
            AppLog.channel("playlist tab failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func playlistFeedPage(
        from playlists: [Playlist]
    ) -> FeedPage {
        playlistLookup = Dictionary(
            uniqueKeysWithValues: playlists.map { ($0.id, $0) }
        )
        return FeedPage(
            videos: playlists.map { self.makePlaylistVideo(from: $0) },
            continuation: nil
        )
    }

    func makePlaylistVideo(
        from playlist: Playlist
    ) -> Video {
        Video(
            id: playlist.id,
            title: playlist.title,
            channelId: nil,
            channelName: "Playlist",
            channelAvatarURL: nil,
            thumbnailURL: playlist.thumbnailURL ?? "",
            viewCount: playlist.itemCount.map { "\($0) videos" },
            publishedAt: nil,
            duration: nil,
            isLive: false
        )
    }

    func openPlaylist(
        _ playlist: Playlist
    ) {
        let controller = PlaylistVideosViewController(
            playlist: playlist,
            service: ServiceContainer.playlists,
            channelViewControllerFactory: channelViewControllerFactory,
            videoRouter: videoRouter
        )
        let targetNav = navigationController?.parent?.navigationController
            ?? navigationController
        targetNav?.pushViewController(controller, animated: true)
    }

    func applyCollectionInsets(
        to collectionView: UICollectionView
    ) {
        let topInset = headerView.expandedHeight + ChannelTabsView.preferredHeight
        collectionView.contentInset.top = topInset
        collectionView.scrollIndicatorInsets.top = topInset
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -topInset),
            animated: false
        )
    }

    func updateScrollInsets(
        for scrollView: UIScrollView
    ) {
        let headerHeight = headerView.heightRef?.constant ?? 0
        scrollView.scrollIndicatorInsets.top = headerHeight
            + ChannelTabsView.preferredHeight
    }
}
