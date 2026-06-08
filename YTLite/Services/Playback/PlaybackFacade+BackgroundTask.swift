import UIKit

extension PlaybackFacade {
    func beginPlaylistSwitchBackgroundTask() {
        endPlaylistSwitchBackgroundTask()
        playlistSwitchBackgroundTask =
            UIApplication.shared.beginBackgroundTask(
                withName: "PlaybackPlaylistSwitch"
            ) { [weak self] in
                self?.endPlaylistSwitchBackgroundTask()
            }
    }

    func endPlaylistSwitchBackgroundTask() {
        guard playlistSwitchBackgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(
            playlistSwitchBackgroundTask
        )
        playlistSwitchBackgroundTask = .invalid
    }
}
