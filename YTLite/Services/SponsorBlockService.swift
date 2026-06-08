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
        "Powered by SponsorBlock (sponsor.ajay.app)"
        + " — an open community project."

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

    private init() {}

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
        URLSession.shared
            .dataTask(with: url) { data, resp, err in
                let result = self.processResponse(
                    data: data,
                    response: resp,
                    error: err,
                    videoId: videoId
                )
                completion(result)
            }
            .resume()
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

    private func processResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        videoId: String
    ) -> Result<[SponsorBlockSegment], Error> {
        if let error {
            return .failure(error)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 {
            AppLog.sponsorBlock("no segments for \(videoId)")
            return .success([])
        }
        guard let data,
              let arr = try? JSONSerialization
                  .jsonObject(with: data) as? [[String: Any]]
        else {
            logParseFailure(code: code, data: data)
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
