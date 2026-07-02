import AVFoundation
import AVKit
import UIKit

// MARK: - Bottom Bar Setup

extension VideoPlayerView {
    func setupBottomBar() {
        setupTimeLabels()
        setupSeekBarCallbacks()
        setupFullscreenButton()
        addBottomBarSubviews()
        activateBottomBarConstraints()
    }

    private func setupTimeLabels() {
        let timeFont = UIFont.monospacedDigitSystemFont(
            ofSize: 12,
            weight: .medium
        )
        currentTimeLabel.font = timeFont
        currentTimeLabel.textColor = .white
        currentTimeLabel.text = "0:00"
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = timeFont
        durationLabel.textColor = UIColor.white
            .withAlphaComponent(0.7)
        durationLabel.text = "0:00"
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupSeekBarCallbacks() {
        seekBar.translatesAutoresizingMaskIntoConstraints = false
        seekBar.onScrubStart = { [weak self] in
            self?.pauseAutoHide()
        }
        seekBar.onScrubEnd = { [weak self] progress in
            guard let self,
                  let currentPlayer = self.player
            else {
                return
            }
            let target = CMTime(
                seconds: progress * self.duration,
                preferredTimescale: 600
            )
            currentPlayer.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            self.scheduleAutoHide()
        }
        seekBar.onScrubChanged = { [weak self] progress in
            guard let self else {
                return
            }
            self.currentTimeLabel.text = formatTime(
                progress * self.duration
            )
        }
    }

    private func setupFullscreenButton() {
        fullscreenButton.setImage(
            PlayerIcons.fullscreen(isFullscreen: false),
            for: .normal
        )
        fullscreenButton.tintColor = .white
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        fullscreenButton.addTarget(
            self,
            action: #selector(fullscreenTapped),
            for: .touchUpInside
        )
    }

    private func addBottomBarSubviews() {
        controlsView.addSubview(currentTimeLabel)
        controlsView.addSubview(seekBar)
        controlsView.addSubview(durationLabel)
        controlsView.addSubview(fullscreenButton)
    }

    private func activateBottomBarConstraints() {
        activateFullscreenConstraints()
        activateDurationConstraints()
        activateCurrentTimeConstraints()
        activateSeekBarConstraints()
    }

    private func activateFullscreenConstraints() {
        let safe = controlsView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            fullscreenButton.bottomAnchor.constraint(
                equalTo: safe.bottomAnchor,
                constant: -16
            ),
            fullscreenButton.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor,
                constant: -16
            ),
            fullscreenButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            fullscreenButton.heightAnchor.constraint(
                equalToConstant: 36
            )
        ])
    }

    private func activateDurationConstraints() {
        NSLayoutConstraint.activate([
            durationLabel.centerYAnchor.constraint(
                equalTo: fullscreenButton.centerYAnchor
            ),
            durationLabel.trailingAnchor.constraint(
                equalTo: fullscreenButton.leadingAnchor,
                constant: -8
            )
        ])
    }

    private func activateCurrentTimeConstraints() {
        let safe = controlsView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            currentTimeLabel.centerYAnchor.constraint(
                equalTo: fullscreenButton.centerYAnchor
            ),
            currentTimeLabel.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor,
                constant: 28
            )
        ])
    }

    private func activateSeekBarConstraints() {
        let safe = controlsView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            seekBar.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor,
                constant: 28
            ),
            seekBar.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor,
                constant: -16
            ),
            seekBar.bottomAnchor.constraint(
                equalTo: fullscreenButton.topAnchor,
                constant: -8
            ),
            seekBar.heightAnchor.constraint(
                equalToConstant: 20
            )
        ])
    }
}
