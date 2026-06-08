import UIKit

final class PlaylistCell: UITableViewCell {
    static let reuseId = "PlaylistCell"

    private let thumb = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(
        style: UITableViewCell.CellStyle,
        reuseIdentifier: String?
    ) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        thumb.layer.cornerRadius = 6
        thumb.layer.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(
            ofSize: 14,
            weight: .medium
        )
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = UIFont.systemFont(ofSize: 12)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumb)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)
        setupCellConstraints()
        applyTheme()
    }

    private func setupCellConstraints() {
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 12
            ),
            thumb.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor
            ),
            thumb.widthAnchor.constraint(equalToConstant: 90),
            thumb.heightAnchor.constraint(equalToConstant: 56),
            titleLabel.leadingAnchor.constraint(
                equalTo: thumb.trailingAnchor,
                constant: 12
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -12
            ),
            titleLabel.topAnchor.constraint(
                equalTo: thumb.topAnchor
            ),
            countLabel.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            countLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 4
            )
        ])
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        titleLabel.textColor = theme.primaryText
        countLabel.textColor = theme.secondaryText
    }

    func configure(with playlist: Playlist) {
        applyTheme()
        titleLabel.text = playlist.title
        if let count = playlist.itemCount {
            countLabel.text = "\(count) videos"
        } else {
            countLabel.text = nil
        }
        if let urlString = playlist.thumbnailURL,
           let url = URL(string: urlString) {
            thumb.setImage(url: url)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.cancel()
        titleLabel.text = nil
        countLabel.text = nil
    }
}
