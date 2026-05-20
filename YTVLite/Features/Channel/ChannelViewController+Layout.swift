import UIKit

extension ChannelViewController {
    func playlistFeedPage(
        from playlists: [Playlist],
        continuation: String? = nil
    ) -> FeedPage {
        playlists.forEach { playlistLookup[$0.id] = $0 }
        return FeedPage(
            videos: playlists.map { self.makePlaylistVideo(from: $0) },
            continuation: continuation
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
        let topInset = baseTabsInset()
        collectionView.contentInset.top = topInset
        collectionView.scrollIndicatorInsets.top = topInset
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -topInset),
            animated: false
        )
    }

    func adjustCollectionInsetsForFilterBar() {
        guard let cv = collectionView else {
            return
        }
        let topInset = baseTabsInset() + ChannelFilterBarView.preferredHeight
        cv.contentInset.top = topInset
        cv.scrollIndicatorInsets.top = topInset
        cv.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
    }

    func updateScrollInsets(for scrollView: UIScrollView) {
        let extra = filterBar.isHidden ? 0 : ChannelFilterBarView.preferredHeight
        scrollView.scrollIndicatorInsets.top =
            (headerView.heightRef?.constant ?? 0)
            + ChannelTabsView.preferredHeight + extra
    }

    func baseTabsInset() -> CGFloat {
        headerView.expandedHeight + ChannelTabsView.preferredHeight
    }

    func updateInfoBarButton(for info: ChannelInfo) {
        let hasAbout = info.description != nil
            || info.contactInfo != nil
            || info.videoCountText != nil
        navigationItem.rightBarButtonItem = hasAbout
            ? infoBarButton : nil
    }
}
