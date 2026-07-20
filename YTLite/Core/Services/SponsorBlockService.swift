import UIKit

// MARK: - Segment model

struct SponsorBlockSegment {
    let uuid: String
    let category: SBCategory
    let startTime: Double
    let endTime: Double
    /// "skip", "poi", "chapter", "full"
    let actionType: String
}

// MARK: - Service

final class SponsorBlockService {
    static let shared = SponsorBlockService()
    static let attributionURL = AppURLs.SponsorBlock.api
    static let attributionText =
        "由SponsorBlock（sponsor.ajay.app）提供技术支持)"
        + " — 一个开放的社区项目."

    static var enabled: Bool {
        get {
            let key = UserDefaultsKeys.SponsorBlock.enabled
            guard UserDefaults.standard.object(forKey: key) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.SponsorBlock.enabled) }
    }

    private let transport: HTTPTransport

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    // MARK: - Per-category settings

    static func skipBehavior(for category: SBCategory) -> SBSkipBehavior {
        let key = UserDefaultsKeys.SponsorBlock
            .segmentBehavior(for: category.rawValue)
        guard let raw = UserDefaults.standard.string(forKey: key),
              let behavior = SBSkipBehavior(rawValue: raw)
        else {
            return category.defaultSkipBehavior
        }
        return behavior
    }

    static func setSkipBehavior(
        _ behavior: SBSkipBehavior,
        for category: SBCategory
    ) {
        let key = UserDefaultsKeys.SponsorBlock
            .segmentBehavior(for: category.rawValue)
        UserDefaults.standard.set(behavior.rawValue, forKey: key)
    }

    // MARK: - API

    /// Fetches segment categories for the given video ID.
    /// Returns an empty array when no segments exist (404).
    func fetchSegments(
        videoId: String,
        completion: @escaping (Result<[SponsorBlockSegment], Error>) -> Void
    ) {
        guard let url = buildSegmentsURL(videoId: videoId) else {
            completion(.failure(sbError("Invalid URL")))
            return
        }
        AppLog.sponsorBlock("fetching segments for \(videoId) url=\(url)")
        transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: nil
        ) { result in
            completion(self.processResult(result, videoId: videoId))
        }
    }

    // MARK: - Private helpers

    private func buildSegmentsURL(videoId: String) -> URL? {
        let allCats = SBCategory.allCases.map { $0.rawValue }
        let catJSON = "["
            + allCats.map { "\"\($0)\"" }.joined(separator: ",")
            + "]"
        let actionJSON = "[\"skip\",\"poi\",\"chapter\",\"full\"]"
        let path = "\(AppURLs.SponsorBlock.api)/api/skipSegments"
        guard var comps = URLComponents(string: path) else {
            return nil
        }
        comps.queryItems = [
            URLQueryItem(name: "videoID", value: videoId),
            URLQueryItem(name: "categories", value: catJSON),
            URLQueryItem(name: "actionTypes", value: actionJSON)
        ]
        return comps.url
    }

    private func processResult(
        _ result: Result<HTTPResponse, Error>,
        videoId: String
    ) -> Result<[SponsorBlockSegment], Error> {
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let response):
            return processResponse(response, videoId: videoId)
        }
    }

    private func processResponse(
        _ response: HTTPResponse,
        videoId: String
    ) -> Result<[SponsorBlockSegment], Error> {
        let code = response.status
        if code == 404 {
            AppLog.sponsorBlock("no segments for \(videoId)")
            return .success([])
        }
        guard let arr = try? JSONSerialization
            .jsonObject(with: response.data) as? [[String: Any]]
        else {
            logParseFailure(code: code, data: response.data)
            return .failure(sbError("Parse error (\(code))", code: 1))
        }
        let segments = parseSegments(from: arr)
        AppLog.sponsorBlock("fetched \(segments.count) segments for \(videoId)")
        return .success(segments)
    }

    private func parseSegments(from arr: [[String: Any]]) -> [SponsorBlockSegment] {
        arr.compactMap { item in
            guard let catStr = item["category"] as? String,
                  let category = SBCategory(rawValue: catStr),
                  let seg = item["segment"] as? [Double],
                  seg.count >= 2,
                  let uuid = item["UUID"] as? String
            else {
                return nil
            }
            let action = item["actionType"] as? String ?? "skip"
            return SponsorBlockSegment(
                uuid: uuid,
                category: category,
                startTime: seg[0],
                endTime: seg[1],
                actionType: action
            )
        }
    }

    private func logParseFailure(code: Int, data: Data?) {
        let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
        AppLog.sponsorBlock("parse failed status=\(code): \(raw.prefix(300))")
    }

    private func sbError(_ message: String, code: Int = 0) -> NSError {
        NSError(
            domain: "SponsorBlock",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
