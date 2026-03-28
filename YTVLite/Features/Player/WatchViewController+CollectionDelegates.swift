import UIKit

// MARK: - UICollectionViewDataSource

extension WatchViewController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleRelatedVideos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: VideoCell.reuseId,
            for: indexPath
        ) as? VideoCell else {
            return UICollectionViewCell()
        }
        guard visibleRelatedVideos.indices.contains(
            indexPath.item
        ) else {
            return cell
        }
        let video = visibleRelatedVideos[indexPath.item]
        let isLandscape =
            view.bounds.width > view.bounds.height
        cell.forceGridLayout = !isLandscape
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

// MARK: - UICollectionViewDelegate

extension WatchViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        !isOuterScrollViewDragging
            && !scrollView.isDecelerating
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard visibleRelatedVideos.indices.contains(
            indexPath.item
        ) else {
            return
        }
        let video = visibleRelatedVideos[indexPath.item]
        VideoRouter.shared.open(
            video: video,
            from: self
        )
    }
}

// MARK: - UIScrollViewDelegate

extension WatchViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        isOuterScrollViewDragging = true
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        if !decelerate {
            isOuterScrollViewDragging = false
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        isOuterScrollViewDragging = false
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        let threshold: CGFloat = 400
        let offset = scrollView.contentOffset.y
            + scrollView.bounds.height
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0,
              offset >= contentHeight - threshold else {
            return
        }
        expandRelatedIfNeeded()
    }
}

// MARK: - PlaybackContext

extension WatchViewController: PlaybackContext {
    func updateStatusLabel(_ text: String) {
        playerStatusLabel.text = text
    }
}
