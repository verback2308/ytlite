import UIKit

extension WatchViewController {
    func activateMetaConstraints() {
        let tl = titleLabel
        let cv = contentView
        let db = descriptionButton
        let dl = descriptionLabel
        NSLayoutConstraint.activate([
            tl.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            tl.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            tl.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            metaLabel.topAnchor.constraint(equalTo: tl.bottomAnchor, constant: 8),
            metaLabel.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            metaLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: db.leadingAnchor, constant: -8
            ),
            db.trailingAnchor.constraint(equalTo: tl.trailingAnchor),
            db.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
            dl.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            dl.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            dl.trailingAnchor.constraint(equalTo: tl.trailingAnchor)
        ])
    }

    func activateChannelConstraints() {
        let av = channelAvatarView
        let cn = channelNameLabel
        let sb = subscribeButton
        NSLayoutConstraint.activate([
            av.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            av.widthAnchor.constraint(equalToConstant: 44),
            av.heightAnchor.constraint(equalToConstant: 44),
            cn.topAnchor.constraint(equalTo: av.topAnchor, constant: 1),
            cn.leadingAnchor.constraint(equalTo: av.trailingAnchor, constant: 12),
            cn.trailingAnchor.constraint(
                lessThanOrEqualTo: sb.leadingAnchor, constant: -12
            ),
            channelMetaLabel.topAnchor.constraint(equalTo: cn.bottomAnchor, constant: 3),
            channelMetaLabel.leadingAnchor.constraint(equalTo: cn.leadingAnchor),
            channelMetaLabel.trailingAnchor.constraint(equalTo: cn.trailingAnchor),
            sb.centerYAnchor.constraint(equalTo: av.centerYAnchor),
            sb.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
        channelTopToMeta = av.topAnchor.constraint(
            equalTo: metaLabel.bottomAnchor, constant: 16
        )
        channelTopToDesc = av.topAnchor.constraint(
            equalTo: descriptionLabel.bottomAnchor, constant: 12
        )
        channelTopToMeta?.isActive = true
    }

    func activateBottomConstraints() {
        let tl = titleLabel
        let ab = actionBar
        let cs = commentsStackView
        let lb = loadMoreCommentsButton
        let cv = contentView
        let rv = relatedCollectionView
        let cl = commentsLabel
        activateActionAndCommentConstraints(
            titleLabel: tl,
            actionBar: ab,
            commentsLabel: cl,
            commentsStack: cs,
            loadMoreButton: lb
        )
        bottomCommentsConstraint = lb.bottomAnchor
            .constraint(equalTo: cv.bottomAnchor, constant: -16)
        relatedPortraitConstraints = [
            rv.topAnchor.constraint(equalTo: lb.bottomAnchor, constant: 20),
            rv.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            rv.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            relatedHeightConstraint,
            rv.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16)
        ].compactMap { $0 }
        NSLayoutConstraint.activate(relatedPortraitConstraints)
    }

    // swiftlint:disable:next function_parameter_count
    private func activateActionAndCommentConstraints(
        titleLabel tl: UILabel,
        actionBar ab: UIStackView,
        commentsLabel cl: UILabel,
        commentsStack cs: UIStackView,
        loadMoreButton lb: UIButton
    ) {
        NSLayoutConstraint.activate([
            ab.topAnchor.constraint(equalTo: channelAvatarView.bottomAnchor, constant: 16),
            ab.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            ab.trailingAnchor.constraint(equalTo: tl.trailingAnchor),
            ab.heightAnchor.constraint(equalToConstant: 52),
            cl.topAnchor.constraint(equalTo: ab.bottomAnchor, constant: 20),
            cl.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            cl.trailingAnchor.constraint(equalTo: tl.trailingAnchor),
            cs.topAnchor.constraint(equalTo: cl.bottomAnchor, constant: 12),
            cs.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            cs.trailingAnchor.constraint(equalTo: tl.trailingAnchor),
            lb.topAnchor.constraint(equalTo: cs.bottomAnchor, constant: 12),
            lb.leadingAnchor.constraint(equalTo: tl.leadingAnchor),
            lb.trailingAnchor.constraint(equalTo: tl.trailingAnchor)
        ])
    }
}
