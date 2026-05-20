import UIKit

final class ChannelTabsView: UIView {
    enum Tab: Int {
        case videos = 0
        case live = 1
        case playlists = 2
    }

    static let preferredHeight: CGFloat = 48

    let segmentedControl = UISegmentedControl(
        items: ["Videos", "Live", "Playlists"]
    )
    var onTabSelected: ((Tab) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupView()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        segmentedControl.backgroundColor = theme.surface
        if #available(iOS 13, *) {
            segmentedControl.selectedSegmentTintColor = theme.accent
            segmentedControl.setTitleTextAttributes(
                [.foregroundColor: theme.primaryText],
                for: .normal
            )
            segmentedControl.setTitleTextAttributes(
                [.foregroundColor: UIColor.white],
                for: .selected
            )
        }
    }

    private func setupView() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = Tab.videos.rawValue
        segmentedControl.addTarget(
            self,
            action: #selector(segmentChanged),
            for: .valueChanged
        )
        addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 12
            ),
            segmentedControl.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -12
            ),
            segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: Self.preferredHeight)
        ])
    }

    @objc
    private func segmentChanged() {
        let selected = Tab(rawValue: segmentedControl.selectedSegmentIndex) ?? .videos
        onTabSelected?(selected)
    }
}
