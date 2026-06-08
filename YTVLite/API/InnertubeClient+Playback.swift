// swiftlint:disable file_length
import Foundation

// MARK: - Playback & Subscriptions
extension InnertubeClient {
    func executeWatchNext(
        video: Video,
        token: String,
        anonymous: Bool = false,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        var body = anonymous ? webContext : tvContext
        body["videoId"] = video.id
        var headers = anonHeaders()
        if !anonymous && !token.isEmpty {
            headers[HTTPHeader.authorization] = "Bearer \(token)"
        }
        let nextURL = "\(baseURL)\(InnertubeEndpoint.next)"
        execute(
            urlString: nextURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "watchNext(\(video.id))"
        ) { json -> WatchPage? in
            InnertubeClient.parseWatchPage(
                json,
                fallbackVideo: video
            )
        } completion: { completion($0) }
    }

    // MARK: Comments

    func executeComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    ) {
        var body = webContext
        body["continuation"] = continuation
            ?? Self.buildCommentsContinuation(
                videoId: videoId,
                sortBy: 0,
                commentId: nil
            )
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.xYoutubeClientName:
                DirectPlaybackClient.web.clientHeaderName,
            HTTPHeader.xYoutubeClientVersion:
                DirectPlaybackClient.web.clientVersion
        ]
        let nextURL = "\(baseURL)\(InnertubeEndpoint.next)"
        execute(
            urlString: nextURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "comments(\(videoId))"
        ) { json -> CommentsPage? in
            Self.parseCommentsPage(json)
        } completion: { completion($0) }
    }

    func executePlayerDebug(
        videoId: String,
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let contexts = buildPlayerDebugContexts()
        let group = DispatchGroup()
        var firstError: Error?
        for ctx in contexts {
            group.enter()
            executePlayer(
                videoId: videoId,
                debugContext: ctx,
                token: ctx.useAuth ? token : nil
            ) { result in
                if case .failure(let error) = result,
                   firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(
                firstError.map { .failure($0) } ?? .success(())
            )
        }
    }

    func executeDirectPlayback(
        videoId: String,
        client: DirectPlaybackClient,
        token: String,
        poToken: String? = nil,
        visitorData: String? = nil,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        let body = buildDirectPlaybackBody(
            videoId: videoId,
            client: client,
            poToken: poToken
        )
        let headers = client.apiHeaders(
            token: token,
            visitorData: visitorData
        )
        let headerKeys = headers.keys.sorted().joined(separator: ",")
        AppLog.innertube(
            "directPlayback(\(client)): "
                + "videoId=\(videoId) headers=\(headerKeys)"
        )
        let playerURL = "\(baseURL)/player\(client.playerURLSuffix)"
        execute(
            urlString: playerURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "directPlayback(\(client))"
        ) { json -> DirectPlaybackInfo? in
            Self.parseDirectPlayback(
                json: json,
                videoId: videoId,
                client: client
            )
        } completion: { completion($0) }
    }

    func executeSubscribe(
        channelId: String,
        token: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["channelIds"] = [channelId]
        AppLog.innertube("executeSubscribe channelId=\(channelId)")
        let subURL = "\(baseURL)\(InnertubeEndpoint.subscribe)"
        execute(
            urlString: subURL,
            body: body,
            headers: authHeaders(token: token),
            cancellationToken: cancellationToken,
            logTag: "subscribe(\(channelId))"
        ) { _ -> Void? in
            ()
        } completion: { completion($0) }
    }

    func executeUnsubscribe(
        channelId: String,
        token: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["channelIds"] = [channelId]
        AppLog.innertube(
            "executeUnsubscribe channelId=\(channelId)"
        )
        let unsubURL = "\(baseURL)\(InnertubeEndpoint.unsubscribe)"
        execute(
            urlString: unsubURL,
            body: body,
            headers: authHeaders(token: token),
            cancellationToken: cancellationToken,
            logTag: "unsubscribe(\(channelId))"
        ) { _ -> Void? in
            ()
        } completion: { completion($0) }
    }

    func executeWatchtimeURLs(
        videoId: String,
        token: String,
        signatureTimestamp: Int?,
        completion: @escaping (WatchtimeURLs?) -> Void
    ) {
        var body = tvContext
        body["videoId"] = videoId
        body["racyCheckOk"] = true
        body["contentCheckOk"] = true
        if let sts = signatureTimestamp {
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "signatureTimestamp": sts
                ]
            ]
        }
        let playerURL =
            "\(baseURL)\(InnertubeEndpoint.player)"
        execute(
            urlString: playerURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "watchtimeURLs(\(videoId))"
        ) { json -> WatchtimeURLs? in
            InnertubeClient.extractWatchtimeURLs(json)
        } completion: { result in
            completion(try? result.get())
        }
    }
}

private extension InnertubeClient {
    struct PlayerDebugContext {
        let name: String
        let body: [String: Any]
        let useAuth: Bool
    }

    static func parseDirectPlayback(
        json: [String: Any],
        videoId: String,
        client: DirectPlaybackClient
    ) -> DirectPlaybackInfo? {
        guard let info = parseDirectPlaybackInfo(json) else {
            logDirectPlaybackError(
                json: json,
                videoId: videoId,
                client: client
            )
            return nil
        }
        let hlsFlag = info.hlsManifestURL != nil
        let progFlag = info.progressiveURL != nil
        let avFlag = info.videoURL != nil && info.audioURL != nil
        AppLog.innertube(
            "directPlayback selected (\(client)) \(videoId): "
                + "hls=\(hlsFlag) prog=\(progFlag) v+a=\(avFlag)"
        )
        return info
    }

    static func logDirectPlaybackError(
        json: [String: Any],
        videoId: String,
        client: DirectPlaybackClient
    ) {
        if let errorObj = json["error"],
           let data = try? JSONSerialization.data(
               withJSONObject: errorObj,
               options: .prettyPrinted
           ),
           let str = String(data: data, encoding: .utf8) {
            AppLog.innertube(
                "directPlayback error (\(client)): \(str)"
            )
        }
        logPlayerDebug(
            videoId: videoId,
            contextName: client.description,
            json: json
        )
    }

    func executePlayer(
        videoId: String,
        debugContext: PlayerDebugContext,
        token: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = debugContext.body
        body["videoId"] = videoId
        if debugContext.name != "TVHTML5" {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
        }
        var headers = anonHeaders()
        if debugContext.name == "WEB" {
            headers[HTTPHeader.xYoutubeClientName] =
                DirectPlaybackClient.web.clientHeaderName
            headers[HTTPHeader.xYoutubeClientVersion] =
                DirectPlaybackClient.web.clientVersion
        }
        if let token {
            headers[HTTPHeader.authorization] = "Bearer \(token)"
        }
        let playerURL = "\(baseURL)\(InnertubeEndpoint.player)"
        execute(
            urlString: playerURL,
            body: body,
            headers: headers,
            logTag: "playerDebug(\(debugContext.name))"
        ) { json -> Void? in
            Self.logPlayerDebug(
                videoId: videoId,
                contextName: debugContext.name,
                json: json
            )
            return ()
        } completion: { completion($0) }
    }

    func buildPlayerDebugContexts() -> [PlayerDebugContext] {
        [
            PlayerDebugContext(name: "TVHTML5", body: tvContext, useAuth: true),
            PlayerDebugContext(name: "WEB", body: webContext, useAuth: false)
        ]
    }

    func buildDirectPlaybackBody(
        videoId: String,
        client: DirectPlaybackClient,
        poToken: String?
    ) -> [String: Any] {
        var body = client.context
        body["videoId"] = videoId
        if client.requiresContentCheckFlags {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        }
        if let poToken, !poToken.isEmpty {
            body["serviceIntegrityDimensions"] = [
                "poToken": poToken
            ]
        }
        return body
    }
}
