import AVFoundation

enum BackgroundPlaybackService {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.Player.backgroundPlayback) }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: UserDefaultsKeys.Player.backgroundPlayback
            )
        }
    }

    /// Call on app launch and whenever the setting changes.
    static func apply() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Always use .playback so Now Playing / remote controls work.
            // Background pause (when isEnabled=false) is handled in appDidEnterBackground.
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            AppLog.player("AVAudioSession error: \(error)")
        }
    }
}
