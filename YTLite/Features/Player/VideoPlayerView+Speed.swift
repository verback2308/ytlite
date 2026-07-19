import UIKit

// MARK: - Playback Speed Controls

extension VideoPlayerView {
    @objc
    func speedTapped() {
        let isVisible = !speedOverlay.isHidden
        speedOverlay.isHidden = isVisible
        if !isVisible {
            pauseAutoHide()
        } else {
            scheduleAutoHide()
        }
    }

    @objc
    func speedSliderChanged(_ slider: UISlider) {
        let snapped = snapToSteps(slider.value)
        slider.value = snapped
        playbackSpeed = snapped
        speedLabel.text = formatSpeedLabel(snapped)
    }

    @objc
    func speedSliderReleased(_ slider: UISlider) {
        let snapped = snapToSteps(slider.value)
        slider.value = snapped
        playbackSpeed = snapped
    }

    func formatSpeedLabel(_ speed: Float) -> String {
        speed == 1.0
            ? "正常"
            : String(format: "%.2g", speed) + "x"
    }

    func snapToSteps(_ value: Float) -> Float {
        let steps: [Float] = [
            0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
        ]
        var closest = steps[0]
        var minDiff = abs(value - closest)
        for step in steps {
            let diff = abs(value - step)
            if diff < minDiff {
                minDiff = diff
                closest = step
            }
        }
        return closest
    }

    func updateSpeedButtonTitle() {
        let title = playbackSpeed == 1.0
            ? "1x"
            : String(format: "%.2g", playbackSpeed) + "x"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white
        ]
        let attributed = NSAttributedString(
            string: title,
            attributes: attrs
        )
        speedButton.setAttributedTitle(
            attributed,
            for: .normal
        )
    }
}
