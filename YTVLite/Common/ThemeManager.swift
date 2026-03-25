import UIKit

enum ThemeMode: String {
    case dark  = "dark"
    case light = "light"
    case auto  = "auto"   // light 07:00–19:00, dark otherwise
}

class ThemeManager {

    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")

    // Cached resolved colors — recomputed only when theme changes
    private(set) var background: UIColor   = .black
    private(set) var surface: UIColor      = UIColor(white: 0.1, alpha: 1)
    private(set) var primaryText: UIColor  = .white
    private(set) var secondaryText: UIColor = UIColor(white: 0.55, alpha: 1)
    private(set) var separator: UIColor    = UIColor(white: 0.15, alpha: 1)
    private(set) var barStyle: UIBarStyle  = .black
    private(set) var statusBarStyle: UIStatusBarStyle = .lightContent

    private init() {
        rebuildCache()
    }

    var themeMode: ThemeMode {
        get {
            let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.Theme.mode) ?? ThemeMode.dark.rawValue
            return ThemeMode(rawValue: raw) ?? .dark
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.Theme.mode)
            rebuildCache()
            applyGlobal()
            NotificationCenter.default.post(name: ThemeManager.didChangeNotification, object: nil)
        }
    }

    var isDark: Bool {
        get {
            switch themeMode {
            case .dark:  return true
            case .light: return false
            case .auto:
                let hour = Calendar.current.component(.hour, from: Date())
                return !(hour >= 7 && hour < 19)
            }
        }
        set { themeMode = newValue ? .dark : .light }
    }

    private func rebuildCache() {
        let dark = isDark
        background    = dark ? .black : UIColor(white: 0.96, alpha: 1)
        surface       = dark ? UIColor(white: 0.1, alpha: 1) : .white
        primaryText   = dark ? .white : UIColor(white: 0.1, alpha: 1)
        secondaryText = dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.45, alpha: 1)
        separator     = dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.88, alpha: 1)
        barStyle      = dark ? .black : .default
        statusBarStyle = dark ? .lightContent : .default
    }

    func applyGlobal() {
        let nav = UINavigationBar.appearance()
        nav.barStyle = barStyle
        nav.tintColor = isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        nav.titleTextAttributes = [.foregroundColor: primaryText]

        let tab = UITabBar.appearance()
        tab.barStyle = barStyle
        tab.tintColor = isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    }
}
