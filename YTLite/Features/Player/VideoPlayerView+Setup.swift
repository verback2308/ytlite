// swiftlint:disable file_length
import AVFoundation
import AVKit
import UIKit

// MARK: - Setup

extension VideoPlayerView {
    func performSetup() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        topGradientLayer.opacity = 0
        bottomGradientLayer.opacity = 0
        layer.addSublayer(topGradientLayer)
        layer.addSublayer(bottomGradientLayer)
        setupControls()
        addGestureRecognizers()
        addLifecycleObservers()
        observeReadyForDisplay()
    }

    /// Unavailable controls stay visible but disabled, so the top-bar
    /// layout never shifts and the user sees the feature exists.
    func setControlAvailability(_ button: UIButton, available: Bool) {
        button.isEnabled = available
        button.alpha = available ? 1 : 0.4
    }

    private func addLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    // MARK: - Gesture Recognizers

    private func addGestureRecognizers() {
        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap)
        )
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        let pinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )
        addGestureRecognizer(pinch)

        let swipeDown = UISwipeGestureRecognizer(
            target: self,
            action: #selector(handleSwipeDown)
        )
        swipeDown.direction = .down
        swipeDown.delegate = self
        addGestureRecognizer(swipeDown)
    }

    // MARK: - Controls Container

    func setupControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.alpha = 0
        addSubview(controlsView)
        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(
                equalTo: topAnchor
            ),
            controlsView.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            controlsView.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            controlsView.bottomAnchor.constraint(
                equalTo: bottomAnchor
            )
        ])
        setupDimOverlay()
        setupSpinner()
        setupSkipButtonTarget()
        setupTopBar()
        setupCenterButtons()
        setupBottomBar()
    }

    private func setupDimOverlay() {
        controlsView.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(
                equalTo: controlsView.topAnchor
            ),
            dimView.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor
            ),
            dimView.trailingAnchor.constraint(
                equalTo: controlsView.trailingAnchor
            ),
            dimView.bottomAnchor.constraint(
                equalTo: controlsView.bottomAnchor
            )
        ])
    }

    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(
                equalTo: centerXAnchor
            ),
            spinner.centerYAnchor.constraint(
                equalTo: centerYAnchor
            )
        ])
    }

    private func setupSkipButtonTarget() {
        skipButton.addTarget(
            self,
            action: #selector(skipButtonTapped),
            for: .touchUpInside
        )
        addSubview(skipButton)
        NSLayoutConstraint.activate([
            skipButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -16
            ),
            skipButton.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -72
            )
        ])
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        settingsButton.setImage(
            PlayerIcons.settings(),
            for: .normal
        )
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(
            self,
            action: #selector(settingsTapped),
            for: .touchUpInside
        )
        controlsView.addSubview(settingsButton)
        configurePipButton()
        configureCCButton()
        configureSpeedButton()
        activateTopBarConstraints()
    }

    private func configurePipButton() {
        pipButton.setImage(
            PlayerIcons.pip(),
            for: .normal
        )
        pipButton.tintColor = .white
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.addTarget(
            self,
            action: #selector(pipTapped),
            for: .touchUpInside
        )
        setControlAvailability(
            pipButton,
            available: isPiPAvailable
        )
        controlsView.addSubview(pipButton)
    }

    private func configureCCButton() {
        styleCCButton()
        ccButton.translatesAutoresizingMaskIntoConstraints = false
        setControlAvailability(ccButton, available: false)
        ccButton.addTarget(
            self,
            action: #selector(ccTapped),
            for: .touchUpInside
        )
        controlsView.addSubview(ccButton)
        setupSubtitleLabel()
    }

    private func configureSpeedButton() {
        speedButton.tintColor = .white
        speedButton.titleLabel?.font = UIFont.systemFont(
            ofSize: 10,
            weight: .bold
        )
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.layer.borderColor = UIColor.white
            .withAlphaComponent(0.6).cgColor
        speedButton.layer.borderWidth = 1
        speedButton.layer.cornerRadius = 4
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        speedButton.addTarget(
            self,
            action: #selector(speedTapped),
            for: .touchUpInside
        )
        controlsView.addSubview(speedButton)
        setupSpeedOverlay()
        updateSpeedButtonTitle()
    }

    private func setupSpeedOverlay() {
        addSubview(speedOverlay)
        speedOverlay.addSubview(speedLabel)
        speedOverlay.addSubview(speedSlider)
        speedLabel.text = "Normal"
        speedSlider.addTarget(
            self,
            action: #selector(speedSliderChanged(_:)),
            for: .valueChanged
        )
        speedSlider.addTarget(
            self,
            action: #selector(speedSliderReleased(_:)),
            for: [.touchUpInside, .touchUpOutside]
        )
        activateSpeedOverlayConstraints()
    }

    private func activateSpeedOverlayConstraints() {
        NSLayoutConstraint.activate([
            speedOverlay.topAnchor.constraint(
                equalTo: speedButton.bottomAnchor,
                constant: 8
            ),
            speedOverlay.centerXAnchor.constraint(
                equalTo: speedButton.centerXAnchor
            ),
            speedOverlay.widthAnchor.constraint(
                equalToConstant: 220
            ),
            speedOverlay.heightAnchor.constraint(
                equalToConstant: 60
            )
        ])
        activateSpeedContentConstraints()
    }

    private func activateSpeedContentConstraints() {
        NSLayoutConstraint.activate([
            speedLabel.topAnchor.constraint(
                equalTo: speedOverlay.topAnchor,
                constant: 8
            ),
            speedLabel.centerXAnchor.constraint(
                equalTo: speedOverlay.centerXAnchor
            ),
            speedSlider.topAnchor.constraint(
                equalTo: speedLabel.bottomAnchor,
                constant: 4
            ),
            speedSlider.leadingAnchor.constraint(
                equalTo: speedOverlay.leadingAnchor,
                constant: 16
            ),
            speedSlider.trailingAnchor.constraint(
                equalTo: speedOverlay.trailingAnchor,
                constant: -16
            )
        ])
    }

    private func styleCCButton() {
        ccButton.setTitle("CC", for: .normal)
        ccButton.titleLabel?.font = UIFont.systemFont(
            ofSize: 12, weight: .bold
        )
        ccButton.tintColor = .white
        ccButton.setTitleColor(.white, for: .normal)
        ccButton.setTitleColor(
            UIColor(red: 1, green: 0.84, blue: 0, alpha: 1),
            for: .selected
        )
        ccButton.layer.borderColor = UIColor.white
            .withAlphaComponent(0.6).cgColor
        ccButton.layer.borderWidth = 1
        ccButton.layer.cornerRadius = 4
    }

    private func setupSubtitleLabel() {
        addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 16
            ),
            subtitleLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -16
            ),
            subtitleLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -56
            )
        ])
    }

    private func activateTopBarConstraints() {
        activateSettingsConstraints()
        activatePipConstraints()
        activateCCConstraints()
        activateSpeedConstraints()
    }

    private func activateSettingsConstraints() {
        let safeArea = controlsView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(
                equalTo: safeArea.topAnchor, constant: 20
            ),
            settingsButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor, constant: -28
            ),
            settingsButton.widthAnchor.constraint(equalToConstant: 36),
            settingsButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func activatePipConstraints() {
        NSLayoutConstraint.activate([
            pipButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            pipButton.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor, constant: -4
            ),
            pipButton.widthAnchor.constraint(equalToConstant: 36),
            pipButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func activateCCConstraints() {
        NSLayoutConstraint.activate([
            ccButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            ccButton.trailingAnchor.constraint(
                equalTo: pipButton.leadingAnchor, constant: -4
            ),
            ccButton.widthAnchor.constraint(equalToConstant: 32),
            ccButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func activateSpeedConstraints() {
        NSLayoutConstraint.activate([
            speedButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            speedButton.trailingAnchor.constraint(
                equalTo: ccButton.leadingAnchor, constant: -4
            ),
            speedButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            speedButton.heightAnchor.constraint(
                equalToConstant: 22
            )
        ])
    }

    // MARK: - Center Buttons

    private func setupCenterButtons() {
        configureRewindButton()
        configurePlayPauseButton()
        configureForwardButton()
        controlsView.addSubview(rewindButton)
        controlsView.addSubview(playPauseButton)
        controlsView.addSubview(forwardButton)
        activateCenterConstraints()
    }

    private func configureRewindButton() {
        rewindButton.setImage(
            PlayerIcons.rewind10(),
            for: .normal
        )
        rewindButton.tintColor = .white
        rewindButton.translatesAutoresizingMaskIntoConstraints = false
        rewindButton.addTarget(
            self,
            action: #selector(rewindTapped),
            for: .touchUpInside
        )
    }

    private func configurePlayPauseButton() {
        playPauseButton.tintColor = .white
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addTarget(
            self,
            action: #selector(playPauseTapped),
            for: .touchUpInside
        )
        updatePlayPauseIcon()
    }

    private func configureForwardButton() {
        forwardButton.setImage(
            PlayerIcons.forward10(),
            for: .normal
        )
        forwardButton.tintColor = .white
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.addTarget(
            self,
            action: #selector(forwardTapped),
            for: .touchUpInside
        )
    }

    private func activateCenterConstraints() {
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(
                equalTo: controlsView.centerXAnchor
            ),
            playPauseButton.centerYAnchor.constraint(
                equalTo: controlsView.centerYAnchor
            ),
            playPauseButton.widthAnchor.constraint(
                equalToConstant: 52
            ),
            playPauseButton.heightAnchor.constraint(
                equalToConstant: 52
            )
        ])
        activateSkipButtonConstraints()
    }

    private func activateSkipButtonConstraints() {
        NSLayoutConstraint.activate([
            rewindButton.centerYAnchor.constraint(
                equalTo: playPauseButton.centerYAnchor
            ),
            rewindButton.trailingAnchor.constraint(
                equalTo: playPauseButton.leadingAnchor,
                constant: -32
            ),
            rewindButton.widthAnchor.constraint(
                equalToConstant: 44
            ),
            rewindButton.heightAnchor.constraint(
                equalToConstant: 44
            ),
            forwardButton.centerYAnchor.constraint(
                equalTo: playPauseButton.centerYAnchor
            ),
            forwardButton.leadingAnchor.constraint(
                equalTo: playPauseButton.trailingAnchor,
                constant: 32
            ),
            forwardButton.widthAnchor.constraint(
                equalToConstant: 44
            ),
            forwardButton.heightAnchor.constraint(
                equalToConstant: 44
            )
        ])
    }
}

// MARK: - System edge-swipe guard

extension VideoPlayerView: UIGestureRecognizerDelegate {
    /// Notification Center / Control Center swipes start at the very top of
    /// the screen and can still reach the app — a swipe-down beginning there
    /// is meant for the system shade, not for exiting fullscreen. Only the
    /// swipe-down recognizer has its delegate set to this view.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard isFullscreen, let window else {
            return true
        }
        return touch.location(in: window).y > 60
    }
}
