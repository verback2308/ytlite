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
        let supported = AVPictureInPictureController
            .isPictureInPictureSupported()
        pipButton.isHidden = !supported
        controlsView.addSubview(pipButton)
    }

    private func activateTopBarConstraints() {
        let safeArea = controlsView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: 10
            ),
            settingsButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -12
            ),
            settingsButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            settingsButton.heightAnchor.constraint(
                equalToConstant: 36
            ),
            pipButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            pipButton.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor,
                constant: -4
            ),
            pipButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            pipButton.heightAnchor.constraint(
                equalToConstant: 36
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
