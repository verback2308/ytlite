import UIKit

// MARK: - Subtitle Handling

extension WatchViewController {
    func showSubtitlePicker() {
        let alert = UIAlertController(
            title: "Subtitles",
            message: nil,
            preferredStyle: .actionSheet
        )
        addOffActionIfNeeded(to: alert)
        addTrackActions(to: alert)
        alert.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: nil
        ))
        configurePopover(for: alert)
        present(alert, animated: true)
    }

    private func addOffActionIfNeeded(
        to alert: UIAlertController
    ) {
        guard activeSubtitleLanguage != nil else {
            return
        }
        alert.addAction(UIAlertAction(
            title: "Off",
            style: .destructive
        ) { [weak self] _ in
            self?.deactivateSubtitles()
        })
    }

    private func addTrackActions(
        to alert: UIAlertController
    ) {
        for track in captionTracks {
            let suffix = track.isAsr ? " (auto)" : ""
            alert.addAction(UIAlertAction(
                title: track.name + suffix,
                style: .default
            ) { [weak self] _ in
                self?.activateSubtitle(track: track)
            })
        }
    }

    private func configurePopover(
        for alert: UIAlertController
    ) {
        guard let popover = alert.popoverPresentationController,
              let ccBtn = videoPlayerView?.ccButton
        else {
            return
        }
        popover.sourceView = ccBtn
        popover.sourceRect = ccBtn.bounds
    }

    func activateSubtitle(track: SubtitleTrack) {
        activeSubtitleLanguage = track.languageCode
        videoPlayerView?.setCaptionTracks(
            captionTracks,
            activeLanguage: track.languageCode
        )
        SubtitleService.shared.load(
            track: track
        ) { [weak self] cues in
            self?.videoPlayerView?.setSubtitleCues(cues)
        }
    }

    func deactivateSubtitles() {
        activeSubtitleLanguage = nil
        videoPlayerView?.clearSubtitles()
        videoPlayerView?.setCaptionTracks(
            captionTracks,
            activeLanguage: nil
        )
    }
}
