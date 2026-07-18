import UIKit

/// Horizontal scrollable chip bar with a single selected chip.
/// Feature-agnostic sibling of ChannelFilterBarView (which is typed
/// to channel filter chips) — takes plain labels and reports taps
/// by index.
final class ChipBarView: UIView {
    static let preferredHeight: CGFloat = 44

    var onSelect: ((Int) -> Void)?

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

    private var buttons: [UIButton] = []
    private var placeholderIndices: IndexSet = []
    private(set) var selectedIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Indices in `placeholders` render as pulsing, non-tappable
    /// skeleton capsules instead of labeled chips.
    func setLabels(
        _ labels: [String],
        selected: Int = 0,
        placeholders: IndexSet = []
    ) {
        selectedIndex = selected
        placeholderIndices = placeholders
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = labels.enumerated().map { idx, label in
            placeholders.contains(idx)
                ? makePlaceholderChip(tag: idx)
                : makeChipButton(label: label, tag: idx)
        }
        buttons.forEach { stack.addArrangedSubview($0) }
        applyTheme()
    }

    func setSelected(_ index: Int) {
        guard index < buttons.count else {
            return
        }
        selectedIndex = index
        applyTheme()
    }

    @objc
    func applyTheme() {
        backgroundColor = ThemeManager.shared.background
        for (idx, btn) in buttons.enumerated() {
            if placeholderIndices.contains(idx) {
                stylePlaceholder(btn)
            } else {
                styleButton(btn, selected: idx == selectedIndex)
            }
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -16)
        ])
        heightAnchor.constraint(
            equalToConstant: Self.preferredHeight
        ).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func makeChipButton(label: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.layer.cornerRadius = 14
        btn.layer.borderWidth = 1
        btn.contentEdgeInsets = UIEdgeInsets(
            top: 6, left: 14, bottom: 6, right: 14
        )
        btn.tag = tag
        btn.addTarget(
            self, action: #selector(chipTapped(_:)), for: .touchUpInside
        )
        return btn
    }

    private func makePlaceholderChip(tag: Int) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.isEnabled = false
        btn.layer.cornerRadius = 14
        btn.tag = tag
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 64),
            btn.heightAnchor.constraint(equalToConstant: 28)
        ])
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        btn.layer.add(pulse, forKey: "chipPulse")
        return btn
    }

    private func stylePlaceholder(_ btn: UIButton) {
        btn.backgroundColor = ThemeManager.shared
            .primaryText.withAlphaComponent(0.12)
    }

    @objc
    private func chipTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx != selectedIndex, idx < buttons.count else {
            return
        }
        setSelected(idx)
        onSelect?(idx)
    }

    private func styleButton(_ btn: UIButton, selected: Bool) {
        let accent = ThemeManager.shared.accent
        let textColor = ThemeManager.shared.primaryText
        if selected {
            btn.backgroundColor = accent
            btn.setTitleColor(ThemeManager.shared.background, for: .normal)
            btn.layer.borderColor = accent.cgColor
        } else {
            btn.backgroundColor = .clear
            btn.setTitleColor(textColor, for: .normal)
            btn.layer.borderColor = textColor.withAlphaComponent(0.3).cgColor
        }
    }
}
