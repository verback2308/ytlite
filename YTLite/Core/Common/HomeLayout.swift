import Foundation

/// How the home feed renders its shelves.
enum HomeLayout: String, CaseIterable {
    /// One continuous grid — shelves merged, no titles.
    case grid = "grid"
    /// Each shelf is a horizontally scrolling rail (TV style).
    case rails = "shelf_rails"

    static var selected: HomeLayout {
        get {
            let raw = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Feed.homeLayout
            )
            return raw.flatMap(HomeLayout.init) ?? .grid
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: UserDefaultsKeys.Feed.homeLayout
            )
            NotificationCenter.default.post(
                name: .homeLayoutSettingDidChange,
                object: nil
            )
        }
    }

    var displayName: String {
        switch self {
        case .grid:
            return "网格"
        case .rails:
            return "列表"
        }
    }
}

extension Notification.Name {
    static let homeLayoutSettingDidChange = Notification.Name(
        "homeLayoutSettingDidChange"
    )
}
