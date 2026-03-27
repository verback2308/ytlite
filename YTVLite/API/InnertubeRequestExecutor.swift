// swiftlint:disable:this file_name
import Foundation

// MARK: - InnertubeRequestExecutor

/// Template Method: the single generic execute routine shared by all Innertube API calls.
/// Eliminates the repeated serialize → post → deserialize → log pattern across
/// InnertubeClientExecute (~20 methods, ~900 lines → ~250 lines after refactor).
extension InnertubeClient {
    /// Executes an Innertube API request, handles serialization, network I/O, and
    /// deserialization, then passes the raw JSON dictionary to `parse`.
    ///
    /// - Parameters:
    ///   - urlString:          Full URL string for the endpoint.
    ///   - body:               Request body dictionary (will be JSON-encoded).
    ///   - headers:            HTTP headers to attach.
    ///   - cancellationToken:  Optional token; if cancelled the completion is silenced.
    ///   - logTag:             Short label used in AppLog for this call (e.g. "browse", "player").
    ///   - parse:              Transforms the JSON dictionary into the expected result type.
    ///                         Return `nil` to signal a parse failure.
    ///   - completion:         Called on an arbitrary queue with success/failure.
    func execute<T>( // swiftlint:disable:this function_parameter_count
        urlString: String,
        body: [String: Any],
        headers: [String: String],
        cancellationToken: CancellationToken? = nil,
        logTag: String = "request",
        parse: @escaping ([String: Any]) -> T?,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        guard let bodyData = try? JSONSerialization.data(
            withJSONObject: body
        ) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        AppLog.innertube(
            "\(logTag): POST \(url.path) bodySize=\(bodyData.count)"
        )

        api.post(
            url: url,
            body: bodyData,
            headers: headers,
            cancellationToken: cancellationToken
        ) { result in
            self.handlePostResult(
                result,
                logTag: logTag,
                parse: parse,
                completion: completion
            )
        }
    }

    private func handlePostResult<T>(
        _ result: Result<Data, Error>,
        logTag: String,
        parse: @escaping ([String: Any]) -> T?,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            AppLog.innertube(
                "\(logTag): request failed — \(error)"
            )
            completion(.failure(error))

        case .success(let data):
            guard let json = try? JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any] else {
                let msg = "\(logTag): JSON decode failed "
                    + "(responseBytes=\(data.count))"
                AppLog.innertube(msg)
                completion(.failure(APIError.decodingFailed))
                return
            }

            guard let result = parse(json) else {
                let keys = json.keys.sorted().joined(separator: ", ")
                AppLog.innertube(
                    "\(logTag): parse failed — topKeys: \(keys)"
                )
                completion(.failure(APIError.decodingFailed))
                return
            }

            AppLog.innertube("\(logTag): success")
            completion(.success(result))
        }
    }

    // MARK: Header helpers

    func authHeaders(token: String) -> [String: String] {
        [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)"
        ]
    }

    func anonHeaders() -> [String: String] {
        [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON]
    }
}
