import AVFoundation
import MediaPlayer

/// Manages Now Playing info and remote command handling (Control Center, AirPods, lock screen).
final class NowPlayingService {
    static let shared = NowPlayingService()

    private weak var player: AVPlayer?
    private var commandTokens: [(MPRemoteCommand, Any)] = []

    private init() {}

    func beginSession(
        player: AVPlayer,
        title: String,
        channelName: String,
        duration: TimeInterval
    ) {
        self.player = player
        publishInfo(
            title: title,
            channelName: channelName,
            duration: duration,
            position: 0
        )
        registerCommands()
    }

    func updatePosition(_ position: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func endSession() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        removeCommands()
        player = nil
    }

    // MARK: - Private

    private func publishInfo(
        title: String,
        channelName: String,
        duration: TimeInterval,
        position: TimeInterval
    ) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: channelName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: player?.rate ?? 1
        ]
    }

    private func registerCommands() {
        removeCommands()
        let center = MPRemoteCommandCenter.shared()
        registerPlayPauseCommands(center)
        registerSeekCommand(center)
    }

    private func registerPlayPauseCommands(
        _ center: MPRemoteCommandCenter
    ) {
        add(center.playCommand) { [weak self] _ in
            self?.player?.play()
            return .success
        }
        add(center.pauseCommand) { [weak self] _ in
            self?.player?.pause()
            return .success
        }
        add(center.togglePlayPauseCommand) { [weak self] _ in
            guard let player = self?.player else {
                return .commandFailed
            }
            if player.rate > 0 { player.pause() } else { player.play() }
            return .success
        }
    }

    private func registerSeekCommand(
        _ center: MPRemoteCommandCenter
    ) {
        add(center.changePlaybackPositionCommand) { [weak self] event in
            guard let ev = event as? MPChangePlaybackPositionCommandEvent,
                  let player = self?.player
            else {
                return .commandFailed
            }
            let target = CMTime(
                seconds: ev.positionTime,
                preferredTimescale: 1_000
            )
            player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            return .success
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let token = command.addTarget(handler: handler)
        commandTokens.append((command, token))
    }

    private func removeCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
            command.isEnabled = false
        }
        commandTokens = []
    }
}
