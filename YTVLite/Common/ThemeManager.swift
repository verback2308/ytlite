import UIKit

class ThemeManager {

    static let shared = ThemeManager()
    static let didChangeNotification = Notification.Name("ThemeManagerDidChange")

    var isDark: Bool {
        get { UserDefaults.standard.object(forKey: "isDarkTheme") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "isDarkTheme")
            applyGlobal()
            NotificationCenter.default.post(name: ThemeManager.didChangeNotification, object: nil)
        }
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
