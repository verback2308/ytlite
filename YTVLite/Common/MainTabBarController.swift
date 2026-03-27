import UIKit

/// Navigation controller that forwards rotation queries to the top view controller.
final class RotatingNavigationController: UINavigationController {
    override var shouldAutorotate: Bool {
        topViewController?.shouldAutorotate ?? super.shouldAutorotate
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        // Blank title on the current top VC → pushed screen's back button shows only chevron
        topViewController?.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain,
                                                                              target: nil, action: nil)
        // Blank title on the pushed VC → any deeper screen's back button also shows only chevron
        viewController.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain,
                                                                          target: nil, action: nil)
        super.pushViewController(viewController, animated: animated)
    }
}

class MainTabBarController: UITabBarController {

    override var shouldAutorotate: Bool {
        selectedViewController?.shouldAutorotate ?? super.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = RotatingNavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Home", image: TabBarIcons.home(), tag: 0)

        let subs = RotatingNavigationController(rootViewController: SubscriptionsViewController())
        subs.tabBarItem = UITabBarItem(title: "Subscriptions", image: TabBarIcons.subscriptions(), tag: 1)

        let library = RotatingNavigationController(rootViewController: LibraryViewController())
        library.tabBarItem = UITabBarItem(title: "Library", image: TabBarIcons.library(), tag: 2)

        viewControllers = [home, subs, library]

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
        applyTheme()
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        tabBar.barStyle = t.barStyle
        tabBar.tintColor = t.isDark ? .white : t.accent
        (viewControllers ?? []).compactMap { $0 as? UINavigationController }.forEach { nav in
            nav.navigationBar.barStyle = t.barStyle
            nav.navigationBar.tintColor = t.isDark ? .white : t.accent
            nav.navigationBar.titleTextAttributes = [.foregroundColor: t.primaryText]
        }
    }
}
