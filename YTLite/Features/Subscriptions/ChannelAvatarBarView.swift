import UIKit

/// Horizontal bar of circular channel avatars shown above the
/// Subscriptions feed, with an "All" button pinned to the right.
final class ChannelAvatarBarView: UIView {
    static let preferredHeight: CGFloat = 88

    var onChannelTapped: ((SubscribedChannel) -> Void)?
    var onAllTapped: (() -> Void)?

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let allButton = UIButton(type: .system)
    private let separator = UIView()
    private var items: [ChannelAvatarItemView] = []
    private var selectedChannelId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setChannels(_ channels: [SubscribedChannel]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items = channels.map { channel in
            let item = ChannelAvatarItemView(channel: channel)
            item.onTap = { [weak self] in
                self?.onChannelTapped?(channel)
            }
            return item
        }
        items.forEach { stack.addArrangedSubview($0) }
        applySelection()
    }

    func setSelectedChannelId(_ id: String?) {
        selectedChannelId = id
        applySelection()
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        separator.backgroundColor = theme.separator
        allButton.setTitleColor(theme.accent, for: .normal)
        items.forEach { $0.applyTheme() }
        applySelection()
    }

    private func applySelection() {
        for item in items {
            item.setSelected(item.channel.id == selectedChannelId)
        }
    }

    @objc
    private func allTapped() {
        onAllTapped?()
    }

    private func setup() {
        addSubview(scrollView)
        scrollView.addSubview(stack)
        setupAllButton()
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(
                equalTo: allButton.leadingAnchor,
                constant: -4
            ),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor,
                constant: 12
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor,
                constant: -12
            ),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        applyTheme()
    }

    private func setupAllButton() {
        allButton.setTitle("全部", for: .normal)
        allButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        allButton.contentEdgeInsets = UIEdgeInsets(
            top: 8, left: 12, bottom: 8, right: 16
        )
        allButton.addTarget(
            self,
            action: #selector(allTapped),
            for: .touchUpInside
        )
        allButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(allButton)
        NSLayoutConstraint.activate([
            allButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            allButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// Single tappable avatar with the channel name underneath and an
/// accent ring when selected.
private final class ChannelAvatarItemView: UIControl {
    static let avatarSize: CGFloat = 48
    static let ringSize: CGFloat = 56
    static let itemWidth: CGFloat = 64

    let channel: SubscribedChannel
    var onTap: (() -> Void)?

    private let ringView = UIView()
    private let avatarView = ChannelAvatarView()
    private let nameLabel = UILabel()
    private var isRingSelected = false

    init(channel: SubscribedChannel) {
        self.channel = channel
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setSelected(_ selected: Bool) {
        isRingSelected = selected
        ringView.layer.borderWidth = selected ? 2 : 0
        ringView.layer.borderColor = ThemeManager.shared.accent.cgColor
        nameLabel.font = .systemFont(
            ofSize: 11,
            weight: selected ? .semibold : .regular
        )
        applyNameColor()
    }

    func applyTheme() {
        avatarView.applyTheme()
        applyNameColor()
    }

    @objc
    private func handleTap() {
        onTap?()
    }

    private func applyNameColor() {
        let theme = ThemeManager.shared
        nameLabel.textColor = isRingSelected
            ? theme.primaryText : theme.secondaryText
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setupRingAndAvatar()
        setupNameLabel()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(
                equalToConstant: ChannelAvatarItemView.itemWidth
            ),
            ringView.topAnchor.constraint(equalTo: topAnchor),
            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarView.centerXAnchor.constraint(
                equalTo: ringView.centerXAnchor
            ),
            avatarView.centerYAnchor.constraint(
                equalTo: ringView.centerYAnchor
            ),
            nameLabel.topAnchor.constraint(
                equalTo: ringView.bottomAnchor,
                constant: 3
            ),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    private func setupRingAndAvatar() {
        let ring = ChannelAvatarItemView.ringSize
        let avatar = ChannelAvatarItemView.avatarSize
        ringView.layer.cornerRadius = ring / 2
        ringView.isUserInteractionEnabled = false
        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)
        avatarView.configure(with: channel)
        addSubview(avatarView)
        NSLayoutConstraint.activate([
            ringView.widthAnchor.constraint(equalToConstant: ring),
            ringView.heightAnchor.constraint(equalToConstant: ring),
            avatarView.widthAnchor.constraint(equalToConstant: avatar),
            avatarView.heightAnchor.constraint(equalToConstant: avatar)
        ])
    }

    private func setupNameLabel() {
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1
        nameLabel.text = channel.title
        nameLabel.isUserInteractionEnabled = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
    }
}
