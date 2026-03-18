import UIKit

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = UINavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Home", image: TabBarIcons.home(), tag: 0)

        let subs = UINavigationController(rootViewController: SubscriptionsViewController())
        subs.tabBarItem = UITabBarItem(title: "Subscriptions", image: TabBarIcons.subscriptions(), tag: 1)

        let profile = UINavigationController(rootViewController: ProfileViewController())
        profile.tabBarItem = UITabBarItem(title: "Profile", image: TabBarIcons.profile(), tag: 2)

        viewControllers = [home, subs, profile]

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        tabBar.barStyle = t.barStyle
        tabBar.tintColor = t.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        (viewControllers ?? []).compactMap { $0 as? UINavigationController }.forEach { nav in
            nav.navigationBar.barStyle = t.barStyle
            nav.navigationBar.tintColor = t.isDark ? .white : UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            nav.navigationBar.titleTextAttributes = [.foregroundColor: t.primaryText]
        }
    }
}
