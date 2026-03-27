import UIKit
import AVFoundation
import AVKit

protocol VideoPlayerViewDelegate: AnyObject {
    func videoPlayerViewDidTapSettings(_ playerView: VideoPlayerView)
    func videoPlayerViewDidTapFullscreen(_ playerView: VideoPlayerView)
}

final class VideoPlayerView: UIView {

    weak var delegate: VideoPlayerViewDelegate?

    // MARK: - Public

    private(set) var player: AVPlayer?

    var isFullscreen: Bool = false {
        didSet { updateFullscreenIcon() }
    }

    func attach(player: AVPlayer) {
        self.player = player
        playerLayer.player = player
        addPeriodicObserver()
        addPlayerObservers()
        updatePlayPauseIcon()
        setupPiP()
    }

    func detach() {
        removePeriodicObserver()
        removePlayerObservers()
        playerLayer.player = nil
        player = nil
        hideSkipButton()
        sponsorSegments = []
        seekBar.setSegments([])
    }

    // MARK: - Layers

    private let playerLayer = AVPlayerLayer()

    private let topGradientLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.colors = [UIColor.black.withAlphaComponent(0.7).cgColor,
                    UIColor.clear.cgColor]
        g.locations = [0, 1]
        return g
    }()

    private let bottomGradientLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.colors = [UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.8).cgColor]
        g.locations = [0, 1]
        return g
    }()

    // MARK: - Controls

    private let controlsView = UIView()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)

    // Top bar
    private let settingsButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private var pipController: AVPictureInPictureController?

    // Center
    private let rewindButton  = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)

    // Bottom bar
    private let seekBar = VideoSeekBar()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let fullscreenButton = UIButton(type: .system)

    // MARK: - Dim overlay

    private let dimView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0.38
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false
        return v
    }()

    // MARK: - SponsorBlock

    /// Called every ~0.5 s with the current playback position in seconds.
    var onTimeUpdate: ((Double) -> Void)?

    /// Called when the user taps the SponsorBlock skip button.
    var onSkipTapped: (() -> Void)?

    private var sponsorSegments: [SponsorBlockSegment] = []

    /// Updates the seekbar segment markers and stores segments for future duration changes.
    func setSponsorSegments(_ segments: [SponsorBlockSegment]) {
        sponsorSegments = segments
        refreshSponsorSeekBar()
    }

    func showSkipButton(categoryName: String) {
        skipButton.setTitle("Skip \(categoryName)", for: .normal)
        skipButton.isHidden = false
    }

    func hideSkipButton() {
        skipButton.isHidden = true
    }

    private let skipButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        b.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        b.layer.borderWidth = 1
        b.layer.cornerRadius = 4
        b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private func refreshSponsorSeekBar() {
        guard duration > 0 else { return }
        let normalized = sponsorSegments
            .filter { SponsorBlockService.skipBehavior(for: $0.category) != .disabled }
            .map { (start: $0.startTime / duration,
                    end:   $0.endTime   / duration,
                    color: $0.category.seekBarColor) }
        seekBar.setSegments(normalized)
    }

    // MARK: - State

    private var timeObserver: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var controlsVisible = false
    private var duration: Double = 0
    private var rateObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        // Gradient layers go on top of playerLayer but below controls — hidden by default
        topGradientLayer.opacity = 0
        bottomGradientLayer.opacity = 0
        layer.addSublayer(topGradientLayer)
        layer.addSublayer(bottomGradientLayer)

        setupControls()

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        addGestureRecognizer(swipeDown)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        topGradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 80)
        bottomGradientLayer.frame = CGRect(x: 0, y: bounds.height - 110, width: bounds.width, height: 110)
    }

    // MARK: - Controls Setup

    private func setupControls() {
        // Controls container fills entire view — hidden by default
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.alpha = 0
        addSubview(controlsView)
        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: topAnchor),
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Dim overlay — first subview so it sits behind all controls
        controlsView.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: controlsView.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor),
        ])

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Skip button — outside controlsView so it stays visible when controls hide
        skipButton.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
        addSubview(skipButton)
        NSLayoutConstraint.activate([
            skipButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            skipButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -72),
        ])

        setupTopBar()
        setupCenterButtons()
        setupBottomBar()
    }

    private func setupTopBar() {
        // Settings button — top right
        settingsButton.setImage(PlayerIcons.settings(), for: .normal)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        controlsView.addSubview(settingsButton)

        // PiP button — left of settings (only if supported)
        pipButton.setImage(PlayerIcons.pip(), for: .normal)
        pipButton.tintColor = .white
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        pipButton.isHidden = !AVPictureInPictureController.isPictureInPictureSupported()
        controlsView.addSubview(pipButton)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.topAnchor, constant: 10),
            settingsButton.trailingAnchor.constraint(equalTo: controlsView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            settingsButton.widthAnchor.constraint(equalToConstant: 36),
            settingsButton.heightAnchor.constraint(equalToConstant: 36),

            pipButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            pipButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -4),
            pipButton.widthAnchor.constraint(equalToConstant: 36),
            pipButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
    }

    @objc private func pipTapped() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    private func setupCenterButtons() {
        // Rewind, play/pause, forward — centered
        rewindButton.setImage(PlayerIcons.rewind10(), for: .normal)
        rewindButton.tintColor = .white
        rewindButton.translatesAutoresizingMaskIntoConstraints = false
        rewindButton.addTarget(self, action: #selector(rewindTapped), for: .touchUpInside)

        playPauseButton.tintColor = .white
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        updatePlayPauseIcon()

        forwardButton.setImage(PlayerIcons.forward10(), for: .normal)
        forwardButton.tintColor = .white
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        controlsView.addSubview(rewindButton)
        controlsView.addSubview(playPauseButton)
        controlsView.addSubview(forwardButton)

        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 52),
            playPauseButton.heightAnchor.constraint(equalToConstant: 52),

            rewindButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            rewindButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -32),
            rewindButton.widthAnchor.constraint(equalToConstant: 44),
            rewindButton.heightAnchor.constraint(equalToConstant: 44),

            forwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 32),
            forwardButton.widthAnchor.constraint(equalToConstant: 44),
            forwardButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupBottomBar() {
        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        currentTimeLabel.font = timeFont
        currentTimeLabel.textColor = .white
        currentTimeLabel.text = "0:00"
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = timeFont
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        durationLabel.text = "0:00"
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.onScrubStart = { [weak self] in self?.pauseAutoHide() }
        seekBar.onScrubEnd = { [weak self] progress in
            guard let self = self, let player = self.player else { return }
            let time = CMTime(seconds: progress * self.duration, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            self.scheduleAutoHide()
        }
        seekBar.onScrubChanged = { [weak self] progress in
            guard let self = self else { return }
            self.currentTimeLabel.text = formatTime(progress * self.duration)
        }

        fullscreenButton.setImage(PlayerIcons.fullscreen(isFullscreen: false), for: .normal)
        fullscreenButton.tintColor = .white
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)

        controlsView.addSubview(currentTimeLabel)
        controlsView.addSubview(seekBar)
        controlsView.addSubview(durationLabel)
        controlsView.addSubview(fullscreenButton)

        NSLayoutConstraint.activate([
            // Fullscreen button — bottom right
            fullscreenButton.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -8),
            fullscreenButton.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -8),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 36),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 36),

            // Duration label — left of fullscreen
            durationLabel.centerYAnchor.constraint(equalTo: fullscreenButton.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor, constant: -4),

            // Current time label — bottom left
            currentTimeLabel.centerYAnchor.constraint(equalTo: fullscreenButton.centerYAnchor),
            currentTimeLabel.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),

            // Seek bar — between time labels, above bottom
            seekBar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),
            seekBar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -12),
            seekBar.bottomAnchor.constraint(equalTo: fullscreenButton.topAnchor, constant: -8),
            seekBar.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Player observers

    private func addPeriodicObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress(time: time)
        }
    }

    private func removePeriodicObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    private func addPlayerObservers() {
        guard let player = player else { return }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updatePlayPauseIcon() }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self?.spinner.startAnimating()
                    self?.setCenter(hidden: true)
                case .playing, .paused:
                    self?.spinner.stopAnimating()
                    self?.setCenter(hidden: false)
                @unknown default:
                    break
                }
            }
        }

        statusObservation = player.currentItem?.observe(\.duration, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                let secs = CMTimeGetSeconds(item.duration)
                if secs.isFinite && secs > 0 {
                    self?.duration = secs
                    self?.durationLabel.text = formatTime(secs)
                    self?.refreshSponsorSeekBar()
                }
            }
        }
    }

    private func removePlayerObservers() {
        rateObservation = nil
        statusObservation = nil
        timeControlObservation = nil
    }

    // MARK: - Progress update

    private func updateProgress(time: CMTime) {
        guard duration > 0 else { return }
        let secs = CMTimeGetSeconds(time)
        currentTimeLabel.text = formatTime(secs)
        if !seekBar.isScrubbing {
            seekBar.setProgress(secs / duration)
        }
        // Buffer
        if let item = player?.currentItem {
            let buffered = item.loadedTimeRanges
                .compactMap { $0 as? CMTimeRange }
                .filter { CMTimeRangeContainsTime($0, time: time) }
                .map { CMTimeGetSeconds($0.start) + CMTimeGetSeconds($0.duration) }
                .max() ?? 0
            seekBar.setBuffer(buffered / duration)
        }
        onTimeUpdate?(secs)
    }

    // MARK: - Show / hide controls

    @objc private func handleTap() {
        if controlsVisible {
            setControls(visible: false, animated: true)
        } else {
            setControls(visible: true, animated: true)
            scheduleAutoHide()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        if x < bounds.width / 2 {
            rewindTapped()
        } else {
            forwardTapped()
        }
        if !controlsVisible {
            setControls(visible: true, animated: true)
        }
        scheduleAutoHide()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .ended else { return }
        if gesture.scale > 1.2 && !isFullscreen {
            delegate?.videoPlayerViewDidTapFullscreen(self)
        } else if gesture.scale < 0.8 && isFullscreen {
            delegate?.videoPlayerViewDidTapFullscreen(self)
        }
    }

    @objc private func handleSwipeDown() {
        guard isFullscreen else { return }
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }

    private func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        let duration = animated ? 0.2 : 0
        UIView.animate(withDuration: duration) {
            self.controlsView.alpha = alpha
            self.topGradientLayer.opacity = visible ? 1 : 0
            self.bottomGradientLayer.opacity = visible ? 1 : 0
        }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.player?.rate ?? 0 > 0 else { return }
            self.setControls(visible: false, animated: true)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func pauseAutoHide() {
        hideWorkItem?.cancel()
    }

    // MARK: - Button actions

    @objc private func playPauseTapped() {
        guard let player = player else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
        scheduleAutoHide()
    }

    @objc private func rewindTapped() {
        guard let player = player else { return }
        let newTime = max(player.currentTime() - CMTime(seconds: 10, preferredTimescale: 600), .zero)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        scheduleAutoHide()
    }

    @objc private func forwardTapped() {
        guard let player = player else { return }
        let newTime = player.currentTime() + CMTime(seconds: 10, preferredTimescale: 600)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        scheduleAutoHide()
    }

    @objc private func skipButtonTapped() {
        onSkipTapped?()
    }

    @objc private func settingsTapped() {
        delegate?.videoPlayerViewDidTapSettings(self)
        scheduleAutoHide()
    }

    @objc private func fullscreenTapped() {
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }

    // MARK: - Icon updates

    private func updatePlayPauseIcon() {
        let isPlaying = (player?.rate ?? 0) > 0
        playPauseButton.setImage(isPlaying ? PlayerIcons.pause() : PlayerIcons.play(), for: .normal)
    }

    private func updateFullscreenIcon() {
        fullscreenButton.setImage(PlayerIcons.fullscreen(isFullscreen: isFullscreen), for: .normal)
    }

    private func setCenter(hidden: Bool) {
        playPauseButton.isHidden = hidden
        rewindButton.isHidden = hidden
        forwardButton.isHidden = hidden
    }
}

// VideoSeekBar and PlayerIcons extracted to separate files

// MARK: - Helpers

private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    } else {
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - PiP Delegate

extension VideoPlayerView: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        pipButton.setImage(PlayerIcons.pipExit(), for: .normal)
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        pipButton.setImage(PlayerIcons.pip(), for: .normal)
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
