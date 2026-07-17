import UIKit

/// "Stats for nerds" panel: a monospaced readout refreshed once per second
/// from a provider closure while visible. Dumb view — all values come from
/// the watch controller.
final class StatsOverlayView: UIView {
    var provider: (() -> String)?
    var onClose: (() -> Void)?

    private let label = UILabel()
    private let closeButton = UIButton(type: .system)
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 6
        layer.masksToBounds = true
        setupLabel()
        setupCloseButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start() {
        refresh()
        let newTimer = Timer.scheduledTimer(
            withTimeInterval: 1, repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        newTimer.tolerance = 0.2
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func refresh() {
        label.text = provider?()
    }

    private func setupLabel() {
        label.font = UIFont(name: "Menlo", size: 10)
            ?? UIFont.systemFont(ofSize: 10)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 10
            ),
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -8
            )
        ])
    }

    private func setupCloseButton() {
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(
            ofSize: 13, weight: .semibold
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(
            self, action: #selector(closeTapped), for: .touchUpInside
        )
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            closeButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: label.trailingAnchor, constant: 4
            )
        ])
    }

    @objc
    private func closeTapped() {
        onClose?()
    }

    deinit {
        timer?.invalidate()
    }
}
