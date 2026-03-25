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

    var displayName: String {
        switch self {
        case .sponsor:         return "Sponsor"
        case .selfpromo:       return "Unpaid/Self Promotion"
        case .exclusiveAccess: return "Exclusive Access"
        case .interaction:     return "Interaction Reminder (Subscribe)"
        case .highlight:       return "Highlight"
        case .intro:           return "Intermission/Intro Animation"
        case .outro:           return "Endcards/Credits"
        case .preview:         return "Preview/Recap"
        case .filler:          return "Tangents/Jokes"
        case .musicOfftopic:   return "Non-Music Section"
        case .chapter:         return "Chapter"
        }
    }

    var categoryDescription: String {
        switch self {
        case .sponsor:
            return "Paid promotion, paid referrals and direct advertisements. Not for self-promotion or free shoutouts to causes/creators/websites/products they like."
        case .selfpromo:
            return "Similar to \"sponsor\" except for unpaid or self promotion. This includes sections about merchandise, donations, or information about who they collaborated with."
        case .exclusiveAccess:
            return "Only for labeling entire videos. Used when a video showcases a product, service or location that they've received free or subsidized access to."
        case .interaction:
            return "When there is a short reminder to like, subscribe or follow in the middle of content. If it is long or about something specific, it should be under self promotion instead."
        case .highlight:
            return "The part of the video that most people are looking for. Similar to \"Video starts at x\" comments."
        case .intro:
            return "An interval without actual content. Could be a pause, static frame, or repeating animation. This should not be used for transitions containing information."
        case .outro:
            return "Credits or when the YouTube endcards appear. Not for conclusions with information."
        case .preview:
            return "Collection of clips that show what is coming up in this video or other videos in a series where all information is repeated later in the video."
        case .filler:
            return "Tangential scenes or jokes that are not required to understand the main content of the video. This should not include segments providing context or background details."
        case .musicOfftopic:
            return "Only for music videos. Non-music part of a music video."
        case .chapter:
            return "Custom named sections of the video."
        }
    }

    var seekBarColor: UIColor {
        switch self {
        case .sponsor:         return UIColor(sbHex: "#00d400")
        case .selfpromo:       return UIColor(sbHex: "#ffff00")
        case .exclusiveAccess: return UIColor(sbHex: "#008000")
        case .interaction:     return UIColor(sbHex: "#cc00ff")
        case .highlight:       return UIColor(sbHex: "#ff1684")
        case .intro:           return UIColor(sbHex: "#00ffff")
        case .outro:           return UIColor(sbHex: "#0202ed")
        case .preview:         return UIColor(sbHex: "#008fd6")
        case .filler:          return UIColor(sbHex: "#7300ab")
        case .musicOfftopic:   return UIColor(sbHex: "#ff9900")
        case .chapter:         return UIColor(sbHex: "#feff01")
        }
    }

    var defaultSkipBehavior: SBSkipBehavior {
        switch self {
        case .sponsor:    return .autoSkip
        default:          return .disabled
        }
    }

    /// Whether this category can be auto-skipped (excludes whole-video / chapter categories)
    var canAutoSkip: Bool {
        switch self {
        case .exclusiveAccess, .chapter: return false
        default: return true
        }
    }

    /// Whether a manual skip button makes sense for this category
    var canShowButton: Bool {
        switch self {
        case .exclusiveAccess, .chapter: return false
        default: return true
        }
    }
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
        if category.canAutoSkip {
            return [.autoSkip, .showButton, .disabled]
        } else if category.canShowButton {
            return [.showButton, .disabled]
        } else {
            return [.disabled]
        }
    }
}

// MARK: - Service

final class SponsorBlockService {
    static let shared = SponsorBlockService()
    private init() {}

    static let attributionURL = "https://sponsor.ajay.app"
    static let attributionText = "Powered by SponsorBlock (sponsor.ajay.app) — an open community project."

    // MARK: - Feature toggle

    static var enabled: Bool {
        get {
            let key = "sponsorblock_enabled"
            guard UserDefaults.standard.object(forKey: key) != nil else { return false }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: "sponsorblock_enabled") }
    }

    // MARK: - Per-category settings

    static func skipBehavior(for category: SBCategory) -> SBSkipBehavior {
        let key = "sb_behavior_\(category.rawValue)"
        guard let raw = UserDefaults.standard.string(forKey: key),
              let behavior = SBSkipBehavior(rawValue: raw)
        else { return category.defaultSkipBehavior }
        return behavior
    }

    static func setSkipBehavior(_ behavior: SBSkipBehavior, for category: SBCategory) {
        UserDefaults.standard.set(behavior.rawValue, forKey: "sb_behavior_\(category.rawValue)")
    }

    // MARK: - API

    /// Fetches all known segment categories for the given video ID.
    /// Returns an empty array (not an error) when no segments exist (HTTP 404).
    func fetchSegments(videoId: String, completion: @escaping (Result<[SponsorBlockSegment], Error>) -> Void) {
        let categories = SBCategory.allCases.map { $0.rawValue }
        let catJSON    = "[" + categories.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let actionJSON = "[\"skip\",\"poi\",\"chapter\",\"full\"]"

        guard var comps = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments") else {
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
