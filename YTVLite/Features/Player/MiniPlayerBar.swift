import AVFoundation
import UIKit

// PiP-style mini player: small floating card in the bottom-right corner.
// Layout: [video 16:9] / [title + ✕]. Tap anywhere → expand.
final class MiniPlayerBar: UIView {
    // MARK: - Subviews

    private let videoContainer = UIView()
    private let thumbnailFallback = ThumbnailImageView(frame: .zero)
    private let infoBar = UIView()
    private let titleLabel = UILabel()
    let closeButton = UIButton(type: .custom)

    // MARK: - State

    var onClose: (() -> Void)?
    var onTap: (() -> Void)?

    private var playerLayer: AVPlayerLayer?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCard()
        setupSubviews()
        setupGestures()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = videoContainer.bounds
    }

    // MARK: - Public API

    func attachPlayer(_ player: AVPlayer?) {
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        guard let newPlayer = player else {
            return
        }
        let layer = AVPlayerLayer(player: newPlayer)
        layer.videoGravity = .resizeAspectFill
        videoContainer.layer.insertSublayer(layer, at: 1)
        playerLayer = layer
        setNeedsLayout()
    }

    func update(title: String, channel: String, isPlaying: Bool, thumbnailURL: String) {
        titleLabel.text = title
        if let url = URL(string: thumbnailURL) {
            thumbnailFallback.setImage(url: url)
        }
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        infoBar.backgroundColor = theme.surface
        titleLabel.textColor = theme.primaryText
        closeButton.setImage(closeIcon(color: theme.primaryText), for: .normal)
    }

    // MARK: - Card setup

    private func setupCard() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        layer.cornerRadius = 10
    }

    // MARK: - Subview setup

    private func setupSubviews() {
        setupVideoContainer()
        setupInfoBar()
        activateConstraints()
    }

    private func setupVideoContainer() {
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.backgroundColor = .black
        videoContainer.clipsToBounds = true

        thumbnailFallback.translatesAutoresizingMaskIntoConstraints = false
        thumbnailFallback.contentMode = .scaleAspectFill
        thumbnailFallback.clipsToBounds = true

        videoContainer.addSubview(thumbnailFallback)
        addSubview(videoContainer)

        NSLayoutConstraint.activate([
            thumbnailFallback.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            thumbnailFallback.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            thumbnailFallback.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            thumbnailFallback.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor)
        ])
    }

    private func setupInfoBar() {
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoBar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        infoBar.addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        infoBar.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: infoBar.topAnchor),
            closeButton.bottomAnchor.constraint(equalTo: infoBar.bottomAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor, constant: -4
            ),
            titleLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor)
        ])
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            // 16:9 aspect ratio
            videoContainer.heightAnchor.constraint(
                equalTo: videoContainer.widthAnchor, multiplier: 9.0 / 16.0
            ),

            infoBar.topAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            infoBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            infoBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
}

// MARK: - Icon drawing + gestures

private extension MiniPlayerBar {
    func closeIcon(color: UIColor) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            color.setStroke()
            let path = UIBezierPath()
            let inset: CGFloat = 7
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.move(to: CGPoint(x: size.width - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: size.height - inset))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.stroke()
        }
        return img.withRenderingMode(.alwaysOriginal)
    }

    func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(barTapped))
        addGestureRecognizer(tap)
    }

    @objc
    func closeTapped() { onClose?() }

    @objc
    func barTapped() { onTap?() }
}
