import UIKit

// MARK: - Segment model

struct SponsorBlockSegment {
    let uuid: String
    let category: SBCategory
    let startTime: Double
    let endTime: Double
    /// "skip", "poi" (point-of-interest / highlight), "chapter", "full"
    let actionType: String
}

// MARK: - Category definition (data-driven — each category declared exactly once)

/// All attributes of a single SponsorBlock category in one place.
/// Adding a new category = adding one entry to `SBCategory.catalog`.
private struct SBCategoryDefinition {
    let displayName: String
    let description: String
    let seekBarColor: UIColor
    let defaultSkipBehavior: SBSkipBehavior
    /// Whether auto-skip is a valid option (false for whole-video / chapter categories).
    let canAutoSkip: Bool
    /// Whether a manual skip button makes sense for this category.
    let canShowButton: Bool

    init(_ name: String, _ desc: String, _ hex: String,
         behavior: SBSkipBehavior = .disabled,
         canAutoSkip: Bool = true,
         canShowButton: Bool = true) {
        displayName         = name
        description         = desc
        seekBarColor        = UIColor(sbHex: hex)
        defaultSkipBehavior = behavior
        self.canAutoSkip    = canAutoSkip
        self.canShowButton  = canShowButton
    }
}

// MARK: - Category

enum SBCategory: String, CaseIterable {
    case sponsor
    case selfpromo
    case exclusiveAccess  = "exclusive_access"
    case interaction
    case highlight
    case intro
    case outro
    case preview
    case filler
    case musicOfftopic    = "music_offtopic"
    case chapter

    // MARK: Catalog — single source of truth for all category metadata

    // swiftlint:disable closure_body_length
    private static let catalog: [SBCategory: SBCategoryDefinition] = {
        typealias D = SBCategoryDefinition
        return [
            .sponsor: D(
                "Sponsor",
                "Paid promotion, paid referrals and direct advertisements. Not for self-promotion or free shoutouts to causes/creators/websites/products they like.",
                "#00d400", behavior: .autoSkip
            ),
            .selfpromo: D(
                "Unpaid/Self Promotion",
                "Similar to \"sponsor\" except for unpaid or self promotion. This includes sections about merchandise, donations, or information about who they collaborated with.",
                "#ffff00"
            ),
            .exclusiveAccess: D(
                "Exclusive Access",
                "Only for labeling entire videos. Used when a video showcases a product, service or location that they've received free or subsidized access to.",
                "#008000", canAutoSkip: false, canShowButton: false
            ),
            .interaction: D(
                "Interaction Reminder (Subscribe)",
                "When there is a short reminder to like, subscribe or follow in the middle of content. If it is long or about something specific, it should be under self promotion instead.",
                "#cc00ff"
            ),
            .highlight: D(
                "Highlight",
                "The part of the video that most people are looking for. Similar to \"Video starts at x\" comments.",
                "#ff1684"
            ),
            .intro: D(
                "Intermission/Intro Animation",
                "An interval without actual content. Could be a pause, static frame, or repeating animation. This should not be used for transitions containing information.",
                "#00ffff"
            ),
            .outro: D(
                "Endcards/Credits",
                "Credits or when the YouTube endcards appear. Not for conclusions with information.",
                "#0202ed"
            ),
            .preview: D(
                "Preview/Recap",
                "Collection of clips that show what is coming up in this video or other videos in a series where all information is repeated later in the video.",
                "#008fd6"
            ),
            .filler: D(
                "Tangents/Jokes",
                "Tangential scenes or jokes that are not required to understand the main content of the video. This should not include segments providing context or background details.",
                "#7300ab"
            ),
            .musicOfftopic: D(
                "Non-Music Section",
                "Only for music videos. Non-music part of a music video.",
                "#ff9900"
            ),
            .chapter: D(
                "Chapter",
                "Custom named sections of the video.",
                "#feff01", canAutoSkip: false, canShowButton: false
            ),
        ]
    }()
    // swiftlint:enable closure_body_length

    // MARK: Derived properties — delegated to catalog (no switch needed)

    private var info: SBCategoryDefinition {
        // catalog covers every case; force-unwrap is safe
        Self.catalog[self]!
    }

    var displayName: String         { info.displayName }
    var categoryDescription: String { info.description }
    var seekBarColor: UIColor       { info.seekBarColor }
    var defaultSkipBehavior: SBSkipBehavior { info.defaultSkipBehavior }
    var canAutoSkip: Bool           { info.canAutoSkip }
    var canShowButton: Bool         { info.canShowButton }
}

// MARK: - Skip behavior

enum SBSkipBehavior: String {
    case autoSkip   = "auto_skip"
    case showButton = "show_button"
    case disabled   = "disabled"

    var displayName: String {
        switch self {
        case .autoSkip:   return "Auto skip"
        case .showButton: return "Show button"
        case .disabled:   return "Disable"
        }
    }

    static func options(for category: SBCategory) -> [SBSkipBehavior] {
        if category.canAutoSkip    { return [.autoSkip, .showButton, .disabled] }
        if category.canShowButton  { return [.showButton, .disabled] }
        return [.disabled]
    }
}

// MARK: - Service

final class SponsorBlockService {
    static let shared = SponsorBlockService()
    private init() {}

    static let attributionURL  = AppURLs.SponsorBlock.api
    static let attributionText = "Powered by SponsorBlock (sponsor.ajay.app) — an open community project."

    // MARK: - Feature toggle

    static var enabled: Bool {
        get {
            let key = UserDefaultsKeys.SponsorBlock.enabled
            guard UserDefaults.standard.object(forKey: key) != nil else { return false }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.SponsorBlock.enabled) }
    }

    // MARK: - Per-category settings

    static func skipBehavior(for category: SBCategory) -> SBSkipBehavior {
        let key = UserDefaultsKeys.SponsorBlock.segmentBehavior(for: category.rawValue)
        guard let raw = UserDefaults.standard.string(forKey: key),
              let behavior = SBSkipBehavior(rawValue: raw)
        else { return category.defaultSkipBehavior }
        return behavior
    }

    static func setSkipBehavior(_ behavior: SBSkipBehavior, for category: SBCategory) {
        let key = UserDefaultsKeys.SponsorBlock.segmentBehavior(for: category.rawValue)
        UserDefaults.standard.set(behavior.rawValue, forKey: key)
    }

    // MARK: - API

    /// Fetches all known segment categories for the given video ID.
    /// Returns an empty array (not an error) when no segments exist (HTTP 404).
    func fetchSegments(videoId: String, completion: @escaping (Result<[SponsorBlockSegment], Error>) -> Void) {
        let categories = SBCategory.allCases.map { $0.rawValue }
        let catJSON    = "[" + categories.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let actionJSON = "[\"skip\",\"poi\",\"chapter\",\"full\"]"

        guard var comps = URLComponents(string: "\(AppURLs.SponsorBlock.api)/api/skipSegments") else {
            completion(.failure(NSError(domain: "SponsorBlock", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])))
            return
        }
        comps.queryItems = [
            URLQueryItem(name: "videoID",     value: videoId),
            URLQueryItem(name: "categories",  value: catJSON),
            URLQueryItem(name: "actionTypes", value: actionJSON),
        ]
        guard let url = comps.url else {
            completion(.failure(NSError(domain: "SponsorBlock", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Could not build URL"])))
            return
        }

        print("[SponsorBlock] fetching segments for videoId=\(videoId) url=\(url)")
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error { completion(.failure(error)); return }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                print("[SponsorBlock] no segments for \(videoId)")
                completion(.success([]))
                return
            }
            guard let data = data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
                print("[SponsorBlock] parse failed status=\(status): \(raw.prefix(300))")
                completion(.failure(NSError(domain: "SponsorBlock", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Parse error (status \(status))"])))
                return
            }

            var segments: [SponsorBlockSegment] = []
            for item in arr {
                guard let catStr     = item["category"]   as? String,
                      let category   = SBCategory(rawValue: catStr),
                      let seg        = item["segment"]    as? [Double], seg.count >= 2,
                      let uuid       = item["UUID"]       as? String
                else { continue }
                let actionType = item["actionType"] as? String ?? "skip"
                segments.append(SponsorBlockSegment(
                    uuid:       uuid,
                    category:   category,
                    startTime:  seg[0],
                    endTime:    seg[1],
                    actionType: actionType
                ))
            }
            print("[SponsorBlock] fetched \(segments.count) segments for \(videoId)")
            completion(.success(segments))
        }.resume()
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    /// Initialise from a CSS hex string, e.g. "#00d400" or "00d400".
    convenience init(sbHex: String) {
        var hex = sbHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >>  8) & 0xFF) / 255
        let b = CGFloat( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
