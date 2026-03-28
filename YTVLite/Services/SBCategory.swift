import UIKit

// MARK: - Category definition (data-driven)

/// All attributes of a single SponsorBlock category.
/// Adding a category = adding one entry to
/// `SBCategory.catalog`.
private struct SBCategoryDefinition {
    let displayName: String
    let description: String
    let seekBarColor: UIColor
    let defaultSkipBehavior: SBSkipBehavior
    /// Whether auto-skip is valid for this category.
    let canAutoSkip: Bool
    /// Whether a manual skip button makes sense.
    let canShowButton: Bool

    init(
        _ name: String,
        _ desc: String,
        _ hex: String,
        behavior: SBSkipBehavior = .disabled,
        canAutoSkip: Bool = true,
        canShowButton: Bool = true
    ) {
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
    case sponsor = "sponsor"
    case selfpromo = "selfpromo"
    case exclusiveAccess = "exclusive_access"
    case interaction = "interaction"
    case highlight = "highlight"
    case intro = "intro"
    case outro = "outro"
    case preview = "preview"
    case filler = "filler"
    case musicOfftopic = "music_offtopic"
    case chapter = "chapter"

    // MARK: Catalog

    // swiftlint:disable closure_body_length
    private static let catalog: [SBCategory: SBCategoryDefinition] = {
        typealias Def = SBCategoryDefinition
        return [
            .sponsor: Def(
                "Sponsor",
                "Paid promotion, paid referrals and direct advertisements."
                    + " Not for self-promotion or free shoutouts to"
                    + " causes/creators/websites/products they like.",
                "#00d400",
                behavior: .autoSkip
            ),
            .selfpromo: Def(
                "Unpaid/Self Promotion",
                "Similar to \"sponsor\" except for unpaid or self promotion."
                    + " This includes sections about merchandise, donations,"
                    + " or information about who they collaborated with.",
                "#ffff00"
            ),
            .exclusiveAccess: Def(
                "Exclusive Access",
                "Only for labeling entire videos. Used when a video"
                    + " showcases a product, service or location that"
                    + " they've received free or subsidized access to.",
                "#008000",
                canAutoSkip: false,
                canShowButton: false
            ),
            .interaction: Def(
                "Interaction Reminder (Subscribe)",
                "When there is a short reminder to like, subscribe or follow"
                    + " in the middle of content. If it is long or about"
                    + " something specific, it should be under self promotion"
                    + " instead.",
                "#cc00ff"
            ),
            .highlight: Def(
                "Highlight",
                "The part of the video that most people are looking for."
                    + " Similar to \"Video starts at x\" comments.",
                "#ff1684"
            ),
            .intro: Def(
                "Intermission/Intro Animation",
                "An interval without actual content. Could be a pause,"
                    + " static frame, or repeating animation. This should"
                    + " not be used for transitions containing information.",
                "#00ffff"
            ),
            .outro: Def(
                "Endcards/Credits",
                "Credits or when the YouTube endcards appear."
                    + " Not for conclusions with information.",
                "#0202ed"
            ),
            .preview: Def(
                "Preview/Recap",
                "Collection of clips that show what is coming up in this"
                    + " video or other videos in a series where all"
                    + " information is repeated later in the video.",
                "#008fd6"
            ),
            .filler: Def(
                "Tangents/Jokes",
                "Tangential scenes or jokes that are not required to"
                    + " understand the main content of the video. This should"
                    + " not include segments providing context or background"
                    + " details.",
                "#7300ab"
            ),
            .musicOfftopic: Def(
                "Non-Music Section",
                "Only for music videos. Non-music part of a music video.",
                "#ff9900"
            ),
            .chapter: Def(
                "Chapter",
                "Custom named sections of the video.",
                "#feff01",
                canAutoSkip: false,
                canShowButton: false
            )
        ]
    }()
    // swiftlint:enable closure_body_length

    // MARK: Derived properties

    private var info: SBCategoryDefinition {
        guard let definition = Self.catalog[self] else {
            fatalError("Missing catalog entry for \(self)")
        }
        return definition
    }

    var displayName: String { info.displayName }
    var categoryDescription: String { info.description }
    var seekBarColor: UIColor { info.seekBarColor }
    var defaultSkipBehavior: SBSkipBehavior { info.defaultSkipBehavior }
    var canAutoSkip: Bool { info.canAutoSkip }
    var canShowButton: Bool { info.canShowButton }
}

// MARK: - Skip behavior

enum SBSkipBehavior: String {
    case autoSkip   = "auto_skip"
    case showButton = "show_button"
    case disabled   = "disabled"

    var displayName: String {
        switch self {
        case .autoSkip:
            return "Auto skip"
        case .showButton:
            return "Show button"
        case .disabled:
            return "Disable"
        }
    }

    static func options(
        for category: SBCategory
    ) -> [SBSkipBehavior] {
        if category.canAutoSkip {
            return [.autoSkip, .showButton, .disabled]
        }
        if category.canShowButton {
            return [.showButton, .disabled]
        }
        return [.disabled]
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    /// Initialise from a CSS hex string, e.g. "#00d400".
    convenience init(sbHex: String) {
        var hex = sbHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
