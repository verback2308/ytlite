import AVFoundation

enum BackgroundPlaybackService {

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.Player.backgroundPlayback) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.Player.backgroundPlayback) }
    }

    /// Call on app launch and whenever the setting changes.
    static func apply() {
        let session = AVAudioSession.sharedInstance()
        do {
            if isEnabled {
                try session.setCategory(.playback, mode: .moviePlayback)
            } else {
                try session.setCategory(.soloAmbient)
            }
            try session.setActive(true)
        } catch {
            print("[BackgroundPlayback] AVAudioSession error: \(error)")
        }
    }
}
