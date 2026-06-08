import UIKit

// MARK: - Subtitle Display

extension VideoPlayerView {
    func setSubtitleCues(_ cues: [SubtitleCue]) {
        subtitleCues = cues
    }

    func clearSubtitles() {
        subtitleCues = []
        subtitleLabel.isHidden = true
        subtitleLabel.text = nil
        ccButton.isSelected = false
    }

    func updateSubtitle(at time: Double) {
        guard !subtitleCues.isEmpty else {
            if !subtitleLabel.isHidden {
                subtitleLabel.isHidden = true
            }
            return
        }
        let cue = subtitleCues.first {
            time >= $0.start && time < $0.end
        }
        if let cue {
            if subtitleLabel.text != cue.text {
                subtitleLabel.text = cue.text
            }
            if subtitleLabel.isHidden {
                subtitleLabel.isHidden = false
            }
        } else {
            if !subtitleLabel.isHidden {
                subtitleLabel.isHidden = true
            }
        }
    }

    func setCaptionTracks(
        _ tracks: [SubtitleTrack],
        activeLanguage: String?
    ) {
        ccButton.isHidden = tracks.isEmpty
        ccButton.isSelected = activeLanguage != nil
    }

    @objc
    func ccTapped() {
        onCCTapped?()
    }
}
