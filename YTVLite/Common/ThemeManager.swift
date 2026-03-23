import UIKit

enum ThemeMode: String {
    case dark  = "dark"
    case light = "light"
    case auto  = "auto"   // light 07:00–19:00, dark otherwise
}

class ThemeManager {

    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")

    var themeMode: ThemeMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "themeMode") ?? "dark"
            return ThemeMode(rawValue: raw) ?? .dark
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "themeMode")
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

    var background: UIColor  { isDark ? .black : UIColor(white: 0.96, alpha: 1) }
    var surface: UIColor     { isDark ? UIColor(white: 0.1, alpha: 1) : .white }
    var primaryText: UIColor { isDark ? .white : UIColor(white: 0.1, alpha: 1) }
    var secondaryText: UIColor { isDark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.45, alpha: 1) }
    var separator: UIColor   { isDark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.88, alpha: 1) }
    var barStyle: UIBarStyle { isDark ? .black : .default }
    var statusBarStyle: UIStatusBarStyle { isDark ? .lightContent : .default }

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
