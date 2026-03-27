import UIKit

final class AutoplayOverlayView: UIView {
    var onPlay: (() -> Void)?
    var onCancel: (() -> Void)?

    private let thumbnailView = ThumbnailImageView(frame: .zero)
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let dimView = UIView()

    private let ringTrack = CAShapeLayer()
    private let ringFill = CAShapeLayer()
    private let countdownLabel = UILabel()

    private let upNextLabel = UILabel()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()

    private let playButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var countdownTimer: Timer?
    private var secondsRemaining: Int = 5
    private var totalSeconds: Int = 5

    init(nextVideo: Video, countdownSecs: Int) {
        super.init(frame: .zero)
        totalSeconds = countdownSecs
        secondsRemaining = countdownSecs
        setupUI()
        configure(with: nextVideo)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)

        upNextLabel.text = "Up Next"
        upNextLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        upNextLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        upNextLabel.textAlignment = .center
        upNextLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(upNextLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        channelLabel.font = .systemFont(ofSize: 11)
        channelLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        channelLabel.textAlignment = .center
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(channelLabel)

        let ringSize: CGFloat = 56
        let ringContainer = UIView()
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringContainer)

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.addSubview(countdownLabel)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor.white.withAlphaComponent(0.85), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 13)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)

        playButton.setTitle("Play now", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        playButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        playButton.layer.cornerRadius = 14
        playButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            ringContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -28),
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),

            countdownLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),

            upNextLabel.bottomAnchor.constraint(equalTo: ringContainer.topAnchor, constant: -8),
            upNextLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            playButton.topAnchor.constraint(equalTo: channelLabel.bottomAnchor, constant: 10),
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -44),

            cancelButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 10),
        ])

        let r = ringSize / 2
        let center = CGPoint(x: r, y: r)
        let path = UIBezierPath(arcCenter: center, radius: r - 4,
                                startAngle: -.pi / 2, endAngle: 3 * .pi / 2,
                                clockwise: true)
        ringTrack.path = path.cgPath
        ringTrack.fillColor = UIColor.clear.cgColor
        ringTrack.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        ringTrack.lineWidth = 3
        ringTrack.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)

        ringFill.path = path.cgPath
        ringFill.fillColor = UIColor.clear.cgColor
        ringFill.strokeColor = UIColor.white.cgColor
        ringFill.lineWidth = 3
        ringFill.lineCap = .round
        ringFill.strokeEnd = 1.0
        ringFill.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)

        ringContainer.layer.addSublayer(ringTrack)
        ringContainer.layer.addSublayer(ringFill)

        countdownLabel.text = "\(secondsRemaining)"
    }

    private func configure(with video: Video) {
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        if let url = URL(string: video.thumbnailURL) {
            thumbnailView.setImage(url: url)
        }
    }

    func startCountdown() {
        countdownLabel.text = "\(secondsRemaining)"
        animateRing()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.secondsRemaining -= 1
            self.countdownLabel.text = "\(self.secondsRemaining)"
            if self.secondsRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.onPlay?()
            }
        }
    }

    private func animateRing() {
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = CFTimeInterval(totalSeconds)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        ringFill.add(anim, forKey: "countdown")
    }

    func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        ringFill.removeAllAnimations()
    }

    @objc private func playTapped() {
        stopCountdown()
        onPlay?()
    }

    @objc private func cancelTapped() {
        stopCountdown()
        onCancel?()
    }
}
