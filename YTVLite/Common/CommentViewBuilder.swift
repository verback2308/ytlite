import UIKit

enum CommentViewBuilder {

    static func makeCommentView(_ comment: Comment) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarView = ThumbnailImageView(frame: .zero)
        avatarView.layer.cornerRadius = 16
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        if let urlString = comment.authorAvatarURL, let url = URL(string: urlString) {
            avatarView.setImage(url: url)
        }

        let authorLabel = UILabel()
        authorLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        authorLabel.textColor = ThemeManager.shared.primaryText
        authorLabel.numberOfLines = 1
        authorLabel.text = comment.isPinned ? "\(comment.authorName) • Pinned" : comment.authorName
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        let metaLabel = UILabel()
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.textColor = ThemeManager.shared.secondaryText
        metaLabel.numberOfLines = 0
        metaLabel.text = [comment.publishedTime, comment.likeCount.map { "\($0) likes" }, comment.replyCount.map { "\($0) replies" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentLabel = UILabel()
        contentLabel.font = UIFont.systemFont(ofSize: 13)
        contentLabel.textColor = ThemeManager.shared.primaryText
        contentLabel.numberOfLines = 0
        contentLabel.text = comment.content
        contentLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = ThemeManager.shared.separator

        container.addSubview(avatarView)
        container.addSubview(authorLabel)
        container.addSubview(metaLabel)
        container.addSubview(contentLabel)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: container.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            authorLabel.topAnchor.constraint(equalTo: container.topAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            contentLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 6),
            contentLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            separator.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}
