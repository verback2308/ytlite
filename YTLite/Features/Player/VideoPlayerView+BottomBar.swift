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
        NSLayoutConstraint.activate([
            fullscreenButton.bottomAnchor.constraint(
                equalTo: controlsView.bottomAnchor,
                constant: -8
            ),
            fullscreenButton.trailingAnchor.constraint(
                equalTo: controlsView.trailingAnchor,
                constant: -8
            ),
            fullscreenButton.widthAnchor.constraint(
                equalToConstant: 36
            ),
            fullscreenButton.heightAnchor.constraint(
                equalToConstant: 36
            )
        ])
        activateTimeLabelConstraints()
        activateSeekBarConstraints()
    }

    private func activateTimeLabelConstraints() {
        NSLayoutConstraint.activate([
            durationLabel.centerYAnchor.constraint(
                equalTo: fullscreenButton.centerYAnchor
            ),
            durationLabel.trailingAnchor.constraint(
                equalTo: fullscreenButton.leadingAnchor,
                constant: -4
            ),
            currentTimeLabel.centerYAnchor.constraint(
                equalTo: fullscreenButton.centerYAnchor
            ),
            currentTimeLabel.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor,
                constant: 12
            )
        ])
    }

    private func activateSeekBarConstraints() {
        NSLayoutConstraint.activate([
            seekBar.leadingAnchor.constraint(
                equalTo: controlsView.leadingAnchor,
                constant: 12
            ),
            seekBar.trailingAnchor.constraint(
                equalTo: controlsView.trailingAnchor,
                constant: -12
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
