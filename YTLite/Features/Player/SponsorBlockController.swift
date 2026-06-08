import AVFoundation

final class SponsorBlockController {
    var segments: [SponsorBlockSegment] = []
    private var activeSegmentUUID: String?
    private weak var playerView: VideoPlayerView?

    func attach(to playerView: VideoPlayerView) {
        self.playerView = playerView
    }

    func reset() {
        segments = []
        activeSegmentUUID = nil
    }

    func checkTime(_ time: Double) {
        guard SponsorBlockService.enabled, !segments.isEmpty
        else { return }

        let active = findActiveSegment(at: time)

        if let seg = active {
            if seg.uuid == activeSegmentUUID {
                return
            }
            activeSegmentUUID = seg.uuid
            handleSegment(seg)
        } else {
            if activeSegmentUUID != nil {
                activeSegmentUUID = nil
                playerView?.hideSkipButton()
            }
        }
    }

    private func findActiveSegment(at time: Double) -> SponsorBlockSegment? {
        segments.first { seg in
            guard seg.actionType == "skip" || seg.actionType == "poi"
            else { return false }
            let behavior = SponsorBlockService.skipBehavior(for: seg.category)
            guard behavior != .disabled
            else { return false }
            return time >= seg.startTime && time < seg.endTime
        }
    }

    private func handleSegment(_ seg: SponsorBlockSegment) {
        let behavior = SponsorBlockService.skipBehavior(for: seg.category)
        switch behavior {
        case .autoSkip:
            guard let player = playerView?.player
            else { return }
            let target = CMTime(
                seconds: seg.endTime, preferredTimescale: 600
            )
            player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            AppLog.sponsorBlock(
                "auto-skipped \(seg.category.displayName) "
                    + "[\(seg.startTime)–\(seg.endTime)]"
            )
        case .showButton:
            playerView?.showSkipButton(
                categoryName: seg.category.displayName
            )
        case .disabled:
            break
        }
    }

    func skipCurrentSegment() {
        guard let uuid = activeSegmentUUID,
              let seg  = segments.first(where: { $0.uuid == uuid }),
              let player = playerView?.player
        else { return }
        let target = CMTime(seconds: seg.endTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        activeSegmentUUID = nil
        playerView?.hideSkipButton()
        AppLog.sponsorBlock(
            "user skipped \(seg.category.displayName) "
                + "[\(seg.startTime)–\(seg.endTime)]"
        )
    }
}
