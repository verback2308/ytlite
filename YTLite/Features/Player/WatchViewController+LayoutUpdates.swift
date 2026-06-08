import UIKit

extension WatchViewController {
    func updateLayoutForSize(_ size: CGSize? = nil) {
        let resolved = size ?? view.bounds.size
        let isLandscape = resolved.width > resolved.height
        if isLandscape {
            activateLandscapeLayout()
        } else {
            activatePortraitLayout()
        }
        relatedCollectionView.backgroundColor = ThemeManager.shared.background
        let expected = isLandscape ? landscapeRelatedLayout : portraitRelatedLayout
        if relatedCollectionView.collectionViewLayout !== expected {
            relatedCollectionView.setCollectionViewLayout(expected, animated: false)
        }
        if !isLandscape { relatedCollectionView.alpha = 1 }
        view.bringSubviewToFront(playerContainer)
        view.bringSubviewToFront(sidebarContainer)
        if let sv = relatedCollectionView.superview {
            sv.setNeedsLayout()
            sv.layoutIfNeeded()
        }
        if relatedCollectionView.bounds.width > 0 {
            updateRelatedLayout(isLandscape: isLandscape, containerSize: resolved)
        }
    }

    func activateLandscapeLayout() {
        scrollTrailingConstraint?.isActive = false
        scrollToSidebarConstraint?.isActive = true
        sidebarTopConstraint?.isActive = true
        sidebarTrailingConstraint?.isActive = true
        sidebarBottomConstraint?.isActive = true
        sidebarWidthConstraint?.isActive = true
        sidebarContainer.isHidden = false
        playerTrailingConstraint?.isActive = false
        playerToSidebarConstraint?.isActive = true
        moveRelatedCollection(toLandscape: true)
        bottomCommentsConstraint?.isActive = true
    }

    func activatePortraitLayout() {
        bottomCommentsConstraint?.isActive = false
        scrollToSidebarConstraint?.isActive = false
        scrollTrailingConstraint?.isActive = true
        sidebarTopConstraint?.isActive = false
        sidebarTrailingConstraint?.isActive = false
        sidebarBottomConstraint?.isActive = false
        sidebarWidthConstraint?.isActive = false
        sidebarContainer.isHidden = true
        playerToSidebarConstraint?.isActive = false
        playerTrailingConstraint?.isActive = true
        moveRelatedCollection(toLandscape: false)
    }

    func updateRelatedLayout(
        isLandscape: Bool,
        containerSize: CGSize? = nil
    ) {
        let layout = isLandscape
            ? landscapeRelatedLayout
            : portraitRelatedLayout
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = isLandscape ? 0 : 6
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: 8, bottom: 12, right: 8
        )
        let size = computeItemSize(
            layout: layout,
            isLandscape: isLandscape,
            containerSize: containerSize
        )
        if layout.itemSize != size {
            layout.itemSize = size
        }
        updateRelatedHeight(
            layout: layout,
            isLandscape: isLandscape,
            itemHeight: size.height
        )
        layout.invalidateLayout()
    }

    func computeItemSize(
        layout: UICollectionViewFlowLayout,
        isLandscape: Bool,
        containerSize: CGSize?
    ) -> CGSize {
        let cols: CGFloat = isLandscape ? 1 : 2
        let inset = layout.sectionInset.left
            + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing
            * (cols - 1)
        let baseWidth: CGFloat
        if let containerSize {
            baseWidth = isLandscape
                ? (sidebarWidthConstraint?.constant ?? 0)
                : containerSize.width
        } else {
            baseWidth = relatedCollectionView.bounds.width
        }
        let available = max(baseWidth - inset - spacing, 120)
        let itemWidth = floor(available / cols)
        let itemHeight = itemWidth * (9.0 / 16.0) + 92
        return CGSize(width: itemWidth, height: itemHeight)
    }

    func updateRelatedHeight(
        layout: UICollectionViewFlowLayout,
        isLandscape: Bool,
        itemHeight: CGFloat
    ) {
        let count = CGFloat(visibleRelatedVideos.count)
        let cols: CGFloat = isLandscape ? 1 : 2
        let rows = count == 0 ? 0 : ceil(count / cols)
        let si = layout.sectionInset
        let total = rows == 0 ? 0 : si.top + si.bottom
            + rows * itemHeight
            + max(0, rows - 1) * layout.minimumLineSpacing
        let desired = isLandscape ? 0 : total
        if relatedHeightConstraint?.constant != desired {
            relatedHeightConstraint?.constant = desired
        }
    }

    func moveRelatedCollection(toLandscape isLandscape: Bool) {
        guard isShowingLandscapeRelated != isLandscape else {
            return
        }
        let old = isLandscape
            ? relatedPortraitConstraints
            : relatedLandscapeConstraints
        NSLayoutConstraint.deactivate(old)
        relatedCollectionView.removeFromSuperview()
        if isLandscape {
            moveLandscapeRelated()
        } else {
            relatedCollectionView.isScrollEnabled = false
            contentView.addSubview(relatedCollectionView)
            NSLayoutConstraint.activate(relatedPortraitConstraints)
        }
        isShowingLandscapeRelated = isLandscape
    }

    private func moveLandscapeRelated() {
        relatedCollectionView.isScrollEnabled = true
        sidebarContainer.addSubview(relatedCollectionView)
        let rv = relatedCollectionView
        let sc = sidebarContainer
        relatedLandscapeConstraints = [
            rv.topAnchor.constraint(equalTo: sc.topAnchor),
            rv.leadingAnchor.constraint(equalTo: sc.leadingAnchor),
            rv.trailingAnchor.constraint(equalTo: sc.trailingAnchor),
            rv.bottomAnchor.constraint(equalTo: sc.bottomAnchor)
        ]
        NSLayoutConstraint.activate(relatedLandscapeConstraints)
    }
}
