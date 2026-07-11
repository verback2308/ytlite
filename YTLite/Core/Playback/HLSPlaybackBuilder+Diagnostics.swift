import Foundation

// MARK: - Range-fetch failure diagnostics

extension HLSPlaybackBuilder {
    /// Verbose dump for a non-2xx range fetch — used to diagnose the iOS 12
    /// pot-stream 403. Logs the full URL + range so the request can be replayed
    /// off-device, the headers we sent, and any body/reason the CDN returned.
    /// Only fires on failure.
    static func logRangeFailure(
        code: Int,
        request: RangeRequest,
        http: HTTPURLResponse?,
        data: Data?
    ) {
        AppLog.hls(
            "range fetch status \(code) range=bytes="
                + "\(request.start)-\(request.end)"
        )
        AppLog.hls("range fetch url=\(request.url.absoluteString)")
        let sent = request.headers
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " | ")
        AppLog.hls("range fetch req-headers: \(sent)")
        if let contentType = http?.allHeaderFields["Content-Type"] {
            AppLog.hls("range fetch resp content-type=\(contentType)")
        }
        if let body = data.flatMap({ String(data: $0, encoding: .utf8) }),
           !body.isEmpty {
            AppLog.hls("range fetch body=\(body.prefix(400))")
        }
    }
}
