import UIKit

extension WatchViewController {
    func showAutoplayOverlay(for video: Video) {
        autoplayOverlay?.removeFromSuperview()
        let overlay = AutoplayOverlayView(
            nextVideo: video,
            countdownSecs: 5
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.onPlay = { [weak self] in
            self?.dismissAutoplayOverlay()
            self?.loadVideo(video)
        }
        overlay.onCancel = { [weak self] in
            self?.dismissAutoplayOverlay()
        }
        playerContainer.addSubview(overlay)
        applyEdgeConstraints(overlay, to: playerContainer)
        autoplayOverlay = overlay
        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
        }
        overlay.startCountdown()
    }

    func applyEdgeConstraints(
        _ child: UIView,
        to parent: UIView
    ) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    func dismissAutoplayOverlay() {
        guard let overlay = autoplayOverlay else {
            return
        }
        autoplayOverlay = nil
        UIView.animate(
            withDuration: 0.2,
            animations: { overlay.alpha = 0 },
            completion: { _ in
                overlay.removeFromSuperview()
            }
        )
    }
}
