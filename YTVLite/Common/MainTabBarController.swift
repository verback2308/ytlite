import UIKit

/// Navigation controller that forwards rotation queries to the top view controller.
final class RotatingNavigationController: UINavigationController {
    override var shouldAutorotate: Bool {
        topViewController?.shouldAutorotate ?? super.shouldAutorotate
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }

    override func pushViewController(
        _ viewController: UIViewController,
        animated: Bool
    ) {
        topViewController?.navigationItem.backBarButtonItem =
            UIBarButtonItem(
                title: "",
                style: .plain,
                target: nil,
                action: nil
            )
        viewController.navigationItem.backBarButtonItem =
            UIBarButtonItem(
                title: "",
                style: .plain,
                target: nil,
                action: nil
            )
        super.pushViewController(viewController, animated: animated)
    }
}

class MainTabBarController: UITabBarController {
    override var shouldAutorotate: Bool {
        selectedViewController?.shouldAutorotate
            ?? super.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = buildTabs()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        applyTheme()
    }

    private func buildTabs() -> [UIViewController] {
        let home = RotatingNavigationController(
            rootViewController: HomeViewController()
        )
        home.tabBarItem = UITabBarItem(
            title: "Home",
            image: TabBarIcons.home(),
            tag: 0
        )

        let subs = RotatingNavigationController(
            rootViewController: SubscriptionsViewController()
        )
        subs.tabBarItem = UITabBarItem(
            title: "Subscriptions",
            image: TabBarIcons.subscriptions(),
            tag: 1
        )

        let library = RotatingNavigationController(
            rootViewController: LibraryViewController()
        )
        library.tabBarItem = UITabBarItem(
            title: "Library",
            image: TabBarIcons.library(),
            tag: 2
        )

        return [home, subs, library]
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        tabBar.barStyle = theme.barStyle
        tabBar.tintColor = theme.isDark ? .white : theme.accent
        let navControllers = (viewControllers ?? [])
            .compactMap { $0 as? UINavigationController }
        for nav in navControllers {
            nav.navigationBar.barStyle = theme.barStyle
            nav.navigationBar.tintColor = theme.isDark
                ? .white : theme.accent
            nav.navigationBar.titleTextAttributes = [
                .foregroundColor: theme.primaryText
            ]
        }
    }
}
