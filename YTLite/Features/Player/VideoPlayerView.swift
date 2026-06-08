import AVFoundation
import AVKit
import UIKit

protocol VideoPlayerViewDelegate: AnyObject {
    func videoPlayerViewDidTapSettings(
        _ playerView: VideoPlayerView
    )
    func videoPlayerViewDidTapFullscreen(
        _ playerView: VideoPlayerView
    )
}

final class VideoPlayerView: UIView {
    // MARK: - Public Properties

    weak var delegate: VideoPlayerViewDelegate?

    var isFullscreen: Bool = false {
        didSet { updateFullscreenIcon() }
    }

    var onTimeUpdate: ((Double) -> Void)?
    var onSkipTapped: (() -> Void)?

    var player: AVPlayer?

    // MARK: - Layers

    let playerLayer = AVPlayerLayer()

    let topGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.7).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.locations = [0, 1]
        return gradient
    }()

    let bottomGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.8).cgColor
        ]
        gradient.locations = [0, 1]
        return gradient
    }()

    // MARK: - Controls

    let controlsView = UIView()
    let spinner = UIActivityIndicatorView(
        style: .whiteLarge
    )
    let settingsButton = UIButton(type: .system)
    let pipButton = UIButton(type: .system)
    var pipController: AVPictureInPictureController?
    let rewindButton = UIButton(type: .system)
    let playPauseButton = UIButton(type: .system)
    let forwardButton = UIButton(type: .system)
    let seekBar = VideoSeekBar()
    let currentTimeLabel = UILabel()
    let durationLabel = UILabel()
    let fullscreenButton = UIButton(type: .system)

    // MARK: - Dim Overlay

    let dimView: UIView = {
        let overlay = UIView()
        overlay.backgroundColor = .black
        overlay.alpha = 0.38
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isUserInteractionEnabled = false
        return overlay
    }()

    // MARK: - SponsorBlock

    var sponsorSegments: [SponsorBlockSegment] = []

    let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(
            ofSize: 14,
            weight: .semibold
        )
        button.backgroundColor = UIColor.black
            .withAlphaComponent(0.75)
        button.layer.borderColor = UIColor.white
            .withAlphaComponent(0.8).cgColor
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 4
        button.contentEdgeInsets = UIEdgeInsets(
            top: 7,
            left: 14,
            bottom: 7,
            right: 14
        )
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - State

    var timeObserver: Any?
    var hideWorkItem: DispatchWorkItem?
    var controlsVisible = false
    var duration: Double = 0
    var rateObservation: NSKeyValueObservation?
    var statusObservation: NSKeyValueObservation?
    var timeControlObservation: NSKeyValueObservation?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        performSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        performSetup()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        topGradientLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: 80
        )
        bottomGradientLayer.frame = CGRect(
            x: 0,
            y: bounds.height - 110,
            width: bounds.width,
            height: 110
        )
    }
}

// MARK: - Helpers

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0:00"
    }
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(
            format: "%d:%02d:%02d",
            hours,
            minutes,
            secs
        )
    }
    return String(
        format: "%d:%02d",
        minutes,
        secs
    )
}
