import AVFoundation

/// Builds an AVMutableComposition from separate video and audio URLs.
enum AdaptiveCompositionBuilder {

    /// Loads video and audio assets, composes them, and returns the resulting AVPlayerItem.
    /// Calls completion on the main queue.
    static func build(videoURL: URL, audioURL: URL, headers: [String: String],
                      completion: @escaping (AVPlayerItem?) -> Void) {
        let startTime = CACurrentMediaTime()
        let assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let videoAsset = AVURLAsset(url: videoURL, options: assetOptions)
        let audioAsset = AVURLAsset(url: audioURL, options: assetOptions)
        let group = DispatchGroup()
        var loadError = false

        group.enter()
        videoAsset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            if videoAsset.statusOfValue(forKey: "tracks", error: &error) != .loaded {
                print("[AdaptiveComposition] video tracks failed: \(error?.localizedDescription ?? "unknown")")
                loadError = true
            }
            group.leave()
        }

        group.enter()
        audioAsset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            if audioAsset.statusOfValue(forKey: "tracks", error: &error) != .loaded {
                print("[AdaptiveComposition] audio tracks failed: \(error?.localizedDescription ?? "unknown")")
                loadError = true
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let elapsed = CACurrentMediaTime() - startTime
            guard !loadError else {
                print(String(format: "[AdaptiveComposition] metadata failed (%.1fs)", elapsed))
                completion(nil)
                return
            }

            guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first,
                  let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first
            else {
                print("[AdaptiveComposition] no video/audio tracks found")
                completion(nil)
                return
            }

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                completion(nil)
                return
            }

            let duration = CMTimeMinimum(videoAsset.duration, audioAsset.duration)
            do {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
                videoTrack.preferredTransform = sourceVideoTrack.preferredTransform
            } catch {
                print("[AdaptiveComposition] composition failed: \(error)")
                completion(nil)
                return
            }

            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 2.0
            print(String(format: "[AdaptiveComposition] ready (%.1fs)", elapsed))
            completion(item)
        }
    }
}
