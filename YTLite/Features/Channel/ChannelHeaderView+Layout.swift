import UIKit

extension ChannelHeaderView {
    func activateConstraints(
        _ parent: UIView,
        _ cv: UICollectionView,
        _ errLabel: UILabel
    ) {
        buildDynamicConstraints()
        var all = frameConstraints(parent)
        all += bannerConstraints()
        all += avatarNameConstraints()
        all += contentConstraints()
        all += skeletonConstraints()
        all += outerConstraints(parent, cv, errLabel)
        NSLayoutConstraint.activate(all)
    }

    private func buildDynamicConstraints() {
        heightRef = heightAnchor.constraint(
            equalToConstant: expandedHeight
        )
        avatarTopRef = avatarView.topAnchor.constraint(
            equalTo: topAnchor, constant: bannerHeight - 32
        )
        nameTopRef = nameLabel.topAnchor.constraint(
            equalTo: avatarView.bottomAnchor, constant: 14
        )
    }

    private func frameConstraints(
        _ parent: UIView
    ) -> [NSLayoutConstraint] {
        guard let heightRef
        else {
            return []
        }
        let safe = parent.safeAreaLayoutGuide
        return [
            topAnchor.constraint(equalTo: safe.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            heightRef
        ]
    }

    private func bannerConstraints() -> [NSLayoutConstraint] {
        let biv = bannerImageView
        let bov = bannerOverlay
        return [
            biv.topAnchor.constraint(equalTo: topAnchor),
            biv.leadingAnchor.constraint(equalTo: leadingAnchor),
            biv.trailingAnchor.constraint(equalTo: trailingAnchor),
            biv.heightAnchor.constraint(equalToConstant: bannerHeight),
            bov.topAnchor.constraint(equalTo: biv.topAnchor),
            bov.leadingAnchor.constraint(equalTo: biv.leadingAnchor),
            bov.trailingAnchor.constraint(equalTo: biv.trailingAnchor),
            bov.bottomAnchor.constraint(equalTo: biv.bottomAnchor)
        ]
    }

    private func avatarNameConstraints() -> [NSLayoutConstraint] {
        guard let avatarTopRef, let nameTopRef
        else {
            return []
        }
        let vb = verifiedBadgeView
        return [
            avatarTopRef,
            avatarView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),
            nameTopRef,
            nameLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 24
            ),
            nameLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -44
            ),
            vb.leadingAnchor.constraint(
                equalTo: nameLabel.trailingAnchor, constant: 4
            ),
            vb.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            vb.widthAnchor.constraint(equalToConstant: 16),
            vb.heightAnchor.constraint(equalToConstant: 16)
        ]
    }

    private func contentConstraints() -> [NSLayoutConstraint] {
        let sl = subscribersLabel
        let sb = subscribeButton
        let sv = separatorView
        return [
            sl.topAnchor.constraint(
                equalTo: nameLabel.bottomAnchor, constant: 6
            ),
            sl.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 24
            ),
            sl.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -24
            ),
            sb.topAnchor.constraint(
                equalTo: sl.bottomAnchor, constant: 14
            ),
            sb.centerXAnchor.constraint(equalTo: centerXAnchor),
            sb.heightAnchor.constraint(equalToConstant: 36),
            sv.topAnchor.constraint(
                equalTo: sb.bottomAnchor, constant: 18
            ),
            sv.leadingAnchor.constraint(equalTo: leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: trailingAnchor),
            sv.heightAnchor.constraint(equalToConstant: 1),
            sv.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
    }

    private func skeletonConstraints() -> [NSLayoutConstraint] {
        let ns = nameSkeleton
        let ss = subsSkeleton
        let bs = btnSkeleton
        let avBottom = avatarView.bottomAnchor
        return [
            ns.topAnchor.constraint(equalTo: avBottom, constant: 14),
            ns.centerXAnchor.constraint(equalTo: centerXAnchor),
            ns.widthAnchor.constraint(equalToConstant: 160),
            ns.heightAnchor.constraint(equalToConstant: 20),
            ss.topAnchor.constraint(
                equalTo: ns.bottomAnchor, constant: 10
            ),
            ss.centerXAnchor.constraint(equalTo: centerXAnchor),
            ss.widthAnchor.constraint(equalToConstant: 110),
            ss.heightAnchor.constraint(equalToConstant: 14),
            bs.topAnchor.constraint(
                equalTo: ss.bottomAnchor, constant: 14
            ),
            bs.centerXAnchor.constraint(equalTo: centerXAnchor),
            bs.widthAnchor.constraint(equalToConstant: 120),
            bs.heightAnchor.constraint(equalToConstant: 36)
        ]
    }

    private func outerConstraints(
        _ parent: UIView,
        _ cv: UICollectionView,
        _ errLabel: UILabel
    ) -> [NSLayoutConstraint] {
        let safe = parent.safeAreaLayoutGuide
        return [
            cv.topAnchor.constraint(equalTo: safe.topAnchor),
            cv.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            cv.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor
            ),
            cv.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            errLabel.centerXAnchor.constraint(
                equalTo: cv.centerXAnchor
            ),
            errLabel.centerYAnchor.constraint(
                equalTo: cv.centerYAnchor
            ),
            errLabel.leadingAnchor.constraint(
                equalTo: parent.leadingAnchor, constant: 32
            ),
            errLabel.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor, constant: -32
            )
        ]
    }
}
