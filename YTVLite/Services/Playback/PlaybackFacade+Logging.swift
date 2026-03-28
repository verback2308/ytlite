import AVFoundation

extension PlaybackFacade {
    func logStartPlayback(
        _ info: DirectPlaybackInfo,
        client: DirectPlaybackClient
    ) {
        let prog = info.progressiveURL?
            .absoluteString.prefix(80) ?? "nil"
        let hls = info.hlsManifestURL != nil
        let dash = info.dashManifestURL != nil
        let vid = info.videoURL != nil
        let aud = info.audioURL != nil
        let sabr = info.serverAbrStreamingURL != nil
        let qual = info.qualityLabel ?? "nil"
        let vis = info.visitorData?
            .prefix(20) ?? "nil"
        AppLog.player(
            "startDirectPlayback (\(client)):"
                + " prog=\(prog)"
                + " hls=\(hls) dash=\(dash)"
                + " vid=\(vid) aud=\(aud)"
                + " sabr=\(sabr)"
                + " quality=\(qual)"
                + " visitor=\(vis)"
        )
    }

    func logSabrInfo(
        _ info: DirectPlaybackInfo,
        client: DirectPlaybackClient
    ) {
        guard let sabrURL =
            info.serverAbrStreamingURL else {
            return
        }
        let vLen = info
            .videoPlaybackUstreamerConfig?.count ?? 0
        let oLen = info
            .onesieUstreamerConfig?.count ?? 0
        let pfx = sabrURL.absoluteString.prefix(80)
        let hasUstreamer = info.hasPlaybackUstreamerConfig
        let msg = "SABR candidate (\(client)):"
            + " \(pfx),"
            + " ustreamer=\(hasUstreamer)"
            + " vLen=\(vLen) oLen=\(oLen)"
        AppLog.player(msg)
    }

    func logPlayDirect(
        _ info: DirectPlaybackInfo
    ) {
        let hls = info.hlsManifestURL != nil
        let dash = info.dashManifestURL != nil
        let prog = info.progressiveURL != nil
        let hasAV = info.videoURL != nil
            && info.audioURL != nil
        let sabr = info.serverAbrStreamingURL != nil
        AppLog.player(
            "playDirectStream:"
                + " hls=\(hls) dash=\(dash)"
                + " prog=\(prog)"
                + " video+audio=\(hasAV)"
                + " sabr=\(sabr)"
        )
    }

    func logOnesieBootstrap(
        _ bootstrap: OnesiePlaybackBootstrap
    ) {
        let types = bootstrap.responseParts
            .map {
                "\($0.type)(c\($0.compressionType))"
            }
            .joined(separator: ",")
        AppLog.player(
            "onesie bootstrap ready"
                + " proxy=\(bootstrap.proxyStatus)"
                + " http=\(bootstrap.httpStatus)"
                + " parts=[\(types)]"
        )
    }
}
