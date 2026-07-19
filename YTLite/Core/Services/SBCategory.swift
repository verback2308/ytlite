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
                "赞助",
                "付费推广、付费引流和直接广告."
                    + " 不包括自我推广"
                    + " 或对他们喜欢的公益\/创作者\/网站\/产品的免费宣传.",
                "#00d400",
                behavior: .autoSkip
            ),
            .selfpromo: Def(
                "无偿\/自我推广",
                "类似「赞助」，但是针对无偿或自我推广的内容."
                    + " 包括周边商品、捐款,"
                    + " 或与他们合作对象相关的信息.",
                "#ffff00"
            ),
            .exclusiveAccess: Def(
                "独家访问",
                "仅用于标记整段视频"
                    + " 当视频展示他们免费"
                    + " 或受补贴获得的产品、服务或地点时使用.",
                "#008000",
                canAutoSkip: false,
                canShowButton: false
            ),
            .interaction: Def(
                "互动提醒（订阅)",
                "内容中间出现的简短点赞、订阅或关注提醒"
                    + " 如果提醒较长或针对特定内容"
                    + " 应归入自我"
                    + " 推广.",
                "#cc00ff"
            ),
            .highlight: Def(
                "重点",
                "视频中大多数人在寻找的部分."
                    + " 类似于「视频从 x 处开始」的评论.",
                "#ff1684"
            ),
            .intro: Def(
                "间隔\/开场动画",
                "没有实际内容的间隔,"
                    + " 可能是暂停、静态画面或循环动画"
                    + " 不应用于包含信息的过渡.",
                "#00ffff"
            ),
            .outro: Def(
                "片尾\/致谢",
                "致谢或 YouTube 片尾画面出现的部分"
                    + " 不应包括提供上下文"
                    + " 不包括带信息的总结.",
                "#0202ed"
            ),
            .preview: Def(
                "预告\/回顾",
                "展示本视频或系列其他视频即将内容的片段合集"
                    + " 所有信息都会在"
                    + " 视频后文重复.",
                "#008fd6"
            ),
            .filler: Def(
                "题外话\/笑话",
                "理解视频主要内容所不需要的离题场景或笑话"
                    + " 不应包括提供上下文"
                    + " 或背景信息的"
                    + " 片段.",
                "#7300ab"
            ),
            .musicOfftopic: Def(
                "非音乐部分",
                "仅用于音乐视频。音乐视频中的非音乐部分.",
                "#ff9900"
            ),
            .chapter: Def(
                "章节",
                "视频中自定义命名的部分.",
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
            return "自动跳过"
        case .showButton:
            return "显示按钮"
        case .disabled:
            return "禁用"
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
