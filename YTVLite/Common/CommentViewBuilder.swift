import UIKit

enum CommentViewBuilder {
    static func makeCommentView(_ comment: Comment) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarView = makeAvatar(comment)
        let authorLabel = makeAuthorLabel(comment)
        let metaLabel = makeMetaLabel(comment)
        let contentLabel = makeContentLabel(comment)
        let separator = makeSeparator()

        for view in [avatarView, authorLabel, metaLabel, contentLabel, separator] {
            container.addSubview(view)
        }

        applyConstraints(
            container: container,
            avatar: avatarView,
            author: authorLabel,
            meta: metaLabel,
            content: contentLabel,
            separator: separator
        )

        return container
    }

    private static func makeAvatar(_ comment: Comment) -> ThumbnailImageView {
        let view = ThumbnailImageView(frame: .zero)
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        if let urlStr = comment.authorAvatarURL,
           let url = URL(string: urlStr) {
            view.setImage(url: url)
        }
        return view
    }

    private static func makeAuthorLabel(_ comment: Comment) -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ThemeManager.shared.primaryText
        label.numberOfLines = 1
        label.text = comment.isPinned
            ? "\(comment.authorName) • Pinned"
            : comment.authorName
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeMetaLabel(_ comment: Comment) -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = ThemeManager.shared.secondaryText
        label.numberOfLines = 0
        label.text = [
            comment.publishedTime,
            comment.likeCount.map { "\($0) likes" },
            comment.replyCount.map { "\($0) replies" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeContentLabel(_ comment: Comment) -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = ThemeManager.shared.primaryText
        label.numberOfLines = 0
        label.text = comment.content
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeSeparator() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = ThemeManager.shared.separator
        return view
    }

    // swiftlint:disable:next function_parameter_count function_body_length
    private static func applyConstraints(
        container: UIView,
        avatar: UIView,
        author: UIView,
        meta: UIView,
        content: UIView,
        separator: UIView
    ) {
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: container.topAnchor),
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),

            author.topAnchor.constraint(equalTo: container.topAnchor),
            author.leadingAnchor.constraint(
                equalTo: avatar.trailingAnchor,
                constant: 12
            ),
            author.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            meta.topAnchor.constraint(
                equalTo: author.bottomAnchor,
                constant: 2
            ),
            meta.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            meta.trailingAnchor.constraint(equalTo: author.trailingAnchor),

            content.topAnchor.constraint(
                equalTo: meta.bottomAnchor,
                constant: 6
            ),
            content.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: author.trailingAnchor),

            separator.topAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: 12
            ),
            separator.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            separator.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            separator.heightAnchor.constraint(
                equalToConstant: 1 / UIScreen.main.scale
            ),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
