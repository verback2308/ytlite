//
//  SZAVPlayer.swift
//
//  Created by CaiSanze on 2019/11/27.
//

import UIKit
import AVFoundation
import CoreAudio
import MediaPlayer
import CoreGraphics

/// AVPlayer observer keys
private let SZPlayerItemStatus = "status"
private let SZPlayerLoadedTimeRanges = "loadedTimeRanges"
private let SZPlayerPlaybackBufferEmpty = "playbackBufferEmpty"
private let SZPlayerPlaybackLikelyToKeepUp = "playbackLikelyToKeepUp"

/// AVPlayer status. You can implement SZAVPlayerDelegate to receive state changes.
public enum SZAVPlayerStatus: Int {
    case loading = 0
    case loadingFailed
    case readyToPlay
    case playEnd
    case playbackStalled
    case bufferBegin
    case bufferEnd
}

/// AVPlayer remote command, e.g. playback related operations from the lock screen. You can
/// implement SZAVPlayerDelegate to receive state changes.
public enum SZAVPlayerRemoteCommand {
    case play
    case pause
    case next
    case previous
}

public protocol SZAVPlayerDelegate: AnyObject {

    /// Playing time delegate.
    /// - Parameters:
    ///   - currentTime: Current item playing time.
    ///   - loadedTime: Current item loaded time.
    ///   - totalTime: Current item total duration.
    func avplayer(_ avplayer: SZAVPlayer, refreshed currentTime: Float64, loadedTime: Float64, totalTime: Float64)

    /// Player status changing delegate.
    /// - Parameters:
    ///   - status: Refer to SZAVPlayerStatus.
    func avplayer(_ avplayer: SZAVPlayer, didChanged status: SZAVPlayerStatus)

    /// Device remote command delegate.
    /// - Parameters:
    ///   - remoteCommand: Refer to SZAVPlayerRemoteCommand
    func avplayer(_ avplayer: SZAVPlayer, didReceived remoteCommand: SZAVPlayerRemoteCommand) -> Bool

    /// If you enabled video output, you can use this delegate to get real-time image object.
    /// - Parameters:
    ///   - videoImage: Real-time video image.
    func avplayer(_ avplayer: SZAVPlayer, didOutput videoImage: CGImage)
}

extension SZAVPlayerDelegate {
    public func avplayer(_ avplayer: SZAVPlayer, didOutput videoImage: CGImage) {}
}

public class SZAVPlayer: UIView {

    public var isMuted: Bool = false {
        didSet {
            player?.isMuted = isMuted
        }
    }
    public weak var delegate: SZAVPlayerDelegate?
    public typealias SeekCompletion = (Bool) -> Void

    public var totalTime: Float64 {
        guard let player = player, let currentItem = player.currentItem else {
            return 0
        }
        
        var time = CMTimeGetSeconds(currentItem.duration)
        if time <= 0 {
            time = CMTimeGetSeconds(currentItem.asset.duration)
        }

        return time.isSafe() ? time : 0
    }

    public var currentTime: Float64 {
        guard let player = player, let currentItem = player.currentItem else {
            return 0
        }

        let time = CMTimeGetSeconds(currentItem.currentTime())
        return time.isSafe() ? time : 0
    }

    private(set) public var playerLayer: AVPlayerLayer?
    private(set) public var player: AVPlayer?
    private(set) public var playerItem: AVPlayerItem?
    private(set) public var currentURLStr: String?
    private(set) public var loadedTime: Float64 = 0

    private lazy var videoOutput: AVPlayerItemVideoOutput = createVideoOutput()
    private let videoOutputQueue: DispatchQueue = DispatchQueue(label: "com.SZAVPlayer.videoOutput")
    private var displayLink: CADisplayLink?
    private var config: SZAVPlayerConfig = SZAVPlayerConfig.default

    private var urlAsset: AVURLAsset?
    private var assetLoader: SZAVPlayerAssetLoader?
    private var isObserverAdded: Bool = false

    private var timeObserver: Any?
    private var isSeeking: Bool = false
    private var isReadyToPlay: Bool = false
    private var isBufferBegin: Bool = false
    private var seekItem: SZAVPlayerSeekItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        SZAVPlayerCache.shared.setup(maxCacheSize: 100)
        setupRemoteTransportControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeNotifications()
        removePlayerObserver()
        removeVideoOutput()
        if let player = player {
            if let currentItem = playerItem {
                removePlayerItemObserver(playerItem: currentItem)
            }

            player.replaceCurrentItem(with: nil)
        }

        delegate = nil
        playerItem = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        playerLayer?.frame = bounds
    }

}

// MARK: - Actions

extension SZAVPlayer {

    // MARK: Public

    /// Setup player with specific url, after successfully loading, the player status will change to ready to play.
    /// - Parameters:
    ///   - config: The config to setup player properly.
    public func setupPlayer(config: SZAVPlayerConfig) {
        guard let url = URL(string: config.urlStr) else { return }

        if let _ = player, let oldAssetLoader = assetLoader {
            oldAssetLoader.cleanup()
            self.assetLoader = nil
        }

        self.config = config
        isReadyToPlay = false
        currentURLStr = config.urlStr
        let assetLoader = createAssetLoader(url: url, uniqueID: config.uniqueID, config: config)
        assetLoader.loadAsset(disableCustomLoading: config.disableCustomLoading) { (asset) in
            if let _ = self.player {
                self.replacePalyerItem(asset: asset)
            } else {
                self.createPlayer(asset: asset)
            }
        }

        self.assetLoader = assetLoader
    }

    /// Replace playerItem with new urlStr and uniqueID.
    /// - Parameters:
    ///   - urlStr: The URL value for playing.
    ///   - uniqueID: The uniqueID to identify wether they are the same audio. If set to nil will use urlStr to create one.
    public func replace(urlStr: String, uniqueID: String?) {
        config.urlStr = urlStr
        config.uniqueID = uniqueID
        setupPlayer(config: config)
    }

    /// If player is ready to play, use this function to start playing.
    public func play() {
        guard let player = player, player.rate == 0 else { return }

        if config.isVideoOutputEnabled {
            videoOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        }
        player.play()
    }

    /// Pause the playing.
    public func pause() {
        guard let player = player, player.rate == 1.0 else { return }

        player.pause()
    }

    /// Reset player to initial time or clean asset completely.
    public func reset(cleanAsset: Bool = false) {
        guard let player = player else { return }

        player.pause()
        if cleanAsset {
            removeVideoOutput()

            if let playerItem = playerItem {
                if isObserverAdded {
                    removePlayerItemObserver(playerItem: playerItem)
                }

                self.playerItem = nil
            }

            player.replaceCurrentItem(with: nil)
            assetLoader?.cleanup()
        } else {
            seekPlayerToTime(time: 0, autoPlay: false) { [weak self] (finished) in
                guard let weakSelf = self, finished else { return }

                if let playerItem = weakSelf.player?.currentItem {
                    let total = CMTimeGetSeconds(playerItem.duration)
                    if total.isSafe() {
                        weakSelf.delegate?.avplayer(weakSelf, refreshed: 0, loadedTime: 0, totalTime: total)
                    }
                }
            }
        }
    }

    /// Move the player cursor to specific time.
    /// - Parameters:
    ///   - time: Target time
    ///   - autoPlay: Whether to play automatically when successfully seek to time.
    ///   - completion: The completion handler for any prior seek request that is still
    ///   in process will be invoked immediately with the finished parameter set to false.
    ///   If the new request completes without being interrupted by another seek request
    ///   or by any other operation the specified completion handler will be invoked with
    ///   the finished parameter set to true.
    public func seekPlayerToTime(time: Float64, autoPlay: Bool = true, completion: SeekCompletion?) {
        guard let player = player, let playerItem = playerItem else { return }

        guard isReadyToPlay else {
            seekItem = SZAVPlayerSeekItem(time: time, autoPlay: autoPlay, completion: completion)
            return
        }

        seekItem = nil
        var total = CMTimeGetSeconds(playerItem.duration)
        total = total.isSafe() ? total : 0
        let isColserToEnd = total > 0 && time > 0 && abs(time - total) <= 0.1
        let didReachEnd = total > 0 && time >= total
        if didReachEnd || isColserToEnd {
            if let completion = completion {
                completion(true)
            }

            handlePlayerStatus(status: .playEnd)
            return
        }

        pause()
        isSeeking = true

        let toTime = CMTimeMakeWithSeconds(time, preferredTimescale: player.currentTime().timescale)
        player.seek(to: toTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] (finished) in
            self?.isSeeking = false

            if finished && autoPlay {
                self?.play()
            }

            if let completion = completion {
                completion(finished)
            }
        }
    }

    /// If you set `isVideoOutputEnabled` to `true` when initialize the config, call this func when you are ready to release the player, otherwise it will cause memory leak.
    public func removeVideoOutput() {
        guard config.isVideoOutputEnabled else { return }

        playerItem?.remove(videoOutput)
        removeDisplayLink()
    }

    // MARK: Private

    private func replacePalyerItem(asset: AVURLAsset) {
        guard let player = player else { return }

        pause()
        removeVideoOutput()

        if let playerItem = playerItem {
            if isObserverAdded {
                removePlayerItemObserver(playerItem: playerItem)
            }

            self.playerItem = nil
        }

        handlePlayerStatus(status: .loading)

        playerItem = AVPlayerItem(asset: asset)
        if let playerItem = playerItem {
            addVideoOutput()
            player.replaceCurrentItem(with: playerItem)
            addPlayerItemObserver(playerItem: playerItem)
        }
    }

    private func addVideoOutput() {
        guard config.isVideoOutputEnabled, let playerItem = playerItem else { return }

        removeVideoOutput()

        displayLink = createDisplayLink()
        playerItem.add(videoOutput)
    }

}

// MARK: - Handles

extension SZAVPlayer {

    private func handlePlayerItemStatus(playerItem: AVPlayerItem) {
        guard playerItem == self.playerItem else {
            return
        }

        switch playerItem.status {
        case .readyToPlay:
            if !isReadyToPlay {
                isReadyToPlay = true
                if let seekItem = seekItem {
                    seekPlayerToTime(time: seekItem.time, autoPlay: seekItem.autoPlay, completion: seekItem.completion)
                    self.seekItem = nil
                } else {
                    handlePlayerStatus(status: .readyToPlay)
                }
            }
        case .failed:
            handlePlayerStatus(status: .loadingFailed)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlayerStatus(status: SZAVPlayerStatus) {
        delegate?.avplayer(self, didChanged: status)
    }

    private func handleLoadedTimeRanges(playerItem: AVPlayerItem) {
        guard let firstRange = playerItem.loadedTimeRanges.first else { return }

        let start = CMTimeGetSeconds(firstRange.timeRangeValue.start)
        let duration = CMTimeGetSeconds(firstRange.timeRangeValue.duration)
        if start.isSafe() && duration.isSafe() {
            loadedTime = start + duration
        }
    }

    @objc func handlePlayToEnd(_ notification: Notification) {
        if let playerItem = playerItem,
            let item = notification.object as? AVPlayerItem,
            playerItem == item
        {
            handlePlayerStatus(status: .playEnd)
        }
    }

    @objc func handlePlaybackStalled(_ notification: Notification) {
        if let playerItem = playerItem,
            let item = notification.object as? AVPlayerItem,
            playerItem == item
        {
            handlePlayerStatus(status: .playbackStalled)
        }
    }

    @objc private func handleDisplayLinkCallback(sender: CADisplayLink) {
        let nextVSync = sender.timestamp + sender.duration
        let outputItemTime = videoOutput.itemTime(forHostTime: nextVSync)
        guard videoOutput.hasNewPixelBuffer(forItemTime: outputItemTime) else { return }

        if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil) {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
            let cgContext = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: CVPixelBufferGetWidth(pixelBuffer),
                                      height: CVPixelBufferGetHeight(pixelBuffer),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo.rawValue)
            if let cgContext = cgContext,
                let cgImage = cgContext.makeImage()
            {
                delegate?.avplayer(self, didOutput: cgImage)
            }

            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
    }

}

// MARK: - Observer

extension SZAVPlayer {

    private func addPlayerObserver() {
        guard let player = player else { return }

        let interval = CMTimeMakeWithSeconds(config.timeObserverInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main, using: { [weak self] (time) in
            guard let weakSelf = self, let playerItem = weakSelf.player?.currentItem else { return }

            if weakSelf.isSeeking {
                return
            }

            let current = CMTimeGetSeconds(time)
            let total = CMTimeGetSeconds(playerItem.duration)
            if current.isSafe() && total.isSafe() {
                weakSelf.delegate?.avplayer(weakSelf, refreshed: current, loadedTime: weakSelf.loadedTime, totalTime: total)
            }
        })
    }

    private func removePlayerObserver() {
        guard let player = player, let timeObserver = timeObserver else { return }

        player.removeTimeObserver(timeObserver)
    }

    private func addPlayerItemObserver(playerItem: AVPlayerItem) {
        isObserverAdded = true
        playerItem.addObserver(self, forKeyPath: SZPlayerItemStatus, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: SZPlayerLoadedTimeRanges, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: SZPlayerPlaybackBufferEmpty, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: SZPlayerPlaybackLikelyToKeepUp, options: .new, context: nil)
    }

    private func removePlayerItemObserver(playerItem: AVPlayerItem) {
        isObserverAdded = false
        playerItem.removeObserver(self, forKeyPath: SZPlayerItemStatus)
        playerItem.removeObserver(self, forKeyPath: SZPlayerLoadedTimeRanges)
        playerItem.removeObserver(self, forKeyPath: SZPlayerPlaybackBufferEmpty)
        playerItem.removeObserver(self, forKeyPath: SZPlayerPlaybackLikelyToKeepUp)
    }

    override public func observeValue(forKeyPath keyPath: String?,
                                      of object: Any?,
                                      change: [NSKeyValueChangeKey : Any]?,
                                      context: UnsafeMutableRawPointer?)
    {
        guard let playerItem = object as? AVPlayerItem else { return }

        switch keyPath {
        case SZPlayerItemStatus:
            handlePlayerItemStatus(playerItem: playerItem)
        case SZPlayerLoadedTimeRanges:
            handleLoadedTimeRanges(playerItem: playerItem)
        case SZPlayerPlaybackBufferEmpty:
            if isReadyToPlay {
                isBufferBegin = true
                handlePlayerStatus(status: .bufferBegin)
            }
        case SZPlayerPlaybackLikelyToKeepUp:
            if isReadyToPlay && isBufferBegin {
                isBufferBegin = false
                handlePlayerStatus(status: .bufferEnd)
            }
        default:
            break
        }
    }

}

// MARK: - Notification

extension SZAVPlayer {

    func addNotificationsForPlayer() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handlePlayToEnd(_:)), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        center.addObserver(self, selector: #selector(handlePlaybackStalled(_:)), name: Notification.Name.AVPlayerItemPlaybackStalled, object: nil)
    }

    func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

}

// MARK: - AudioSession

extension SZAVPlayer {

    public static func activeAudioSession(category: AVAudioSession.Category = .playback,
                                          options: AVAudioSession.SetActiveOptions = [])
    {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(category)
            try session.setActive(true, options: options)
        } catch {
            SZLogError("ActiveAudioSession failed.")
        }
    }

    public static func deactiveAudioSession(category: AVAudioSession.Category = .ambient,
                                            options: AVAudioSession.SetActiveOptions = [.notifyOthersOnDeactivation])
    {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(false, options: options)
        } catch {
            SZLogError("DeactiveAudioSession failed.")
        }
    }

    public func setupNowPlaying(title: String, description: String, image: UIImage?) {
        var nowPlayingInfo = [String : Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = description

        if let image = image {
            let mediaItem = MPMediaItemArtwork(boundsSize: image.size) { size in
                return image
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaItem
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playerItem?.currentTime().seconds
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = playerItem?.asset.duration.seconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] event in
            guard let weakSelf = self else {
                return .commandFailed
            }

            return weakSelf.handleRemoteCommand(remoteCommand: .play)
        }

        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let weakSelf = self else {
                return .commandFailed
            }

            return weakSelf.handleRemoteCommand(remoteCommand: .pause)
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let weakSelf = self else {
                return .commandFailed
            }

            return weakSelf.handleRemoteCommand(remoteCommand: .next)
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let weakSelf = self else {
                return .commandFailed
            }

            return weakSelf.handleRemoteCommand(remoteCommand: .previous)
        }
    }

    private func handleRemoteCommand(remoteCommand: SZAVPlayerRemoteCommand) -> MPRemoteCommandHandlerStatus {
        if let executeSucceed = delegate?.avplayer(self, didReceived: remoteCommand), executeSucceed {
            return .success
        }

        return .commandFailed
    }

}

// MARK: - SZAVPlayerItemDelegate

extension SZAVPlayer: SZAVPlayerAssetLoaderDelegate {

    public func assetLoaderDidFinishDownloading(_ assetLoader: SZAVPlayerAssetLoader) {
        SZLogInfo("did finish downloading")
    }

    public func assetLoader(_ assetLoader: SZAVPlayerAssetLoader, didDownload bytes: Int64) {
        //        SZLogInfo("did download \(bytes)/\(expectedToReceive)")
    }

    public func assetLoader(_ assetLoader: SZAVPlayerAssetLoader, downloadingFailed error: Error) {
        SZLogError(String(describing: error))
    }

}

// MARK: - AVPlayerItemOutputPullDelegate

extension SZAVPlayer: AVPlayerItemOutputPullDelegate {

    public func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        displayLink?.isPaused = false
    }

}

// MARK: - Getter

extension SZAVPlayer {

    private func createPlayer(asset: AVURLAsset) {
        handlePlayerStatus(status: .loading)

        playerItem = AVPlayerItem(asset: asset)
        addVideoOutput()
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = isMuted
        player?.automaticallyWaitsToMinimizeStalling = false

        if config.isVideo {
            createPlayerLayer(videoGravity: config.videoGravity)
        }
        addPlayerObserver()
        addPlayerItemObserver(playerItem: playerItem!)
        addNotificationsForPlayer()
    }

    private func createAssetLoader(url: URL, uniqueID: String?, config: SZAVPlayerConfig) -> SZAVPlayerAssetLoader {
        let loader = SZAVPlayerAssetLoader(url: url, config: config)
        let finalUniqueID = uniqueID ?? SZAVPlayerFileSystem.uniqueID(url: url)
        loader.uniqueID = finalUniqueID
        loader.delegate = self

        return loader
    }

    private func createPlayerLayer(videoGravity: AVLayerVideoGravity = .resizeAspect) {
        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = videoGravity

        self.layer.addSublayer(layer)
        playerLayer = layer
    }

    private func createVideoOutput() -> AVPlayerItemVideoOutput {
        let settings: [String: Any] = [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)]
        let videoOutput = AVPlayerItemVideoOutput(outputSettings: settings)
        videoOutput.setDelegate(self, queue: videoOutputQueue)

        return videoOutput
    }

    private func createDisplayLink() -> CADisplayLink {
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkCallback))
        link.preferredFramesPerSecond = 25
        link.add(to: RunLoop.current, forMode: .default)
        link.isPaused = true

        return link
    }

    private func removeDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

}

private extension Float64 {

    func isSafe() -> Bool {
        if isNaN || isInfinite {
            return false
        }

        return true
    }

}
