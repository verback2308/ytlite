import Foundation

/// Uses a native HLS manifest URL — preferred path, handled entirely by AVPlayer.
struct HLSPlaybackStrategy: PlaybackStrategy {
    func canHandle(_ info: DirectPlaybackInfo) -> Bool {
        info.hlsManifestURL != nil
    }

    func play(_ info: DirectPlaybackInfo, client: DirectPlaybackClient, context: PlaybackContext) {
        guard let url = info.hlsManifestURL else {
            return
        }
        AppLog.player("strategy: HLS \(url.absoluteString.prefix(120))...")
        context.updateStatusLabel("Loading HLS stream...")
        context.attachPlayer(url: url)
    }
}
