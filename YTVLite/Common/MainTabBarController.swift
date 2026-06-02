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
    private let dependencies: AppDependencies
    private weak var playerPanel: PlayerPanelViewController?
    private var miniPlayerBar: MiniPlayerBar?
    private var miniPlayerBarBottomConstraint: NSLayoutConstraint?

    override var shouldAutorotate: Bool {
        selectedViewController?.shouldAutorotate
            ?? super.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
        ToolbarManager.shared.searchViewControllerFactory = { [dependencies] in
            dependencies.makeSearchViewController()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        [makeHomeTab(), makeSubscriptionsTab(), makeLibraryTab()]
    }

    private func makeHomeTab() -> UIViewController {
        let home = RotatingNavigationController(
            rootViewController: HomeViewController(
                service: dependencies.feedService,
                channelViewControllerFactory:
                    dependencies.makeChannelViewController
            )
        )
        home.tabBarItem = UITabBarItem(
            title: "Home",
            image: TabBarIcons.home(),
            tag: 0
        )
        return home
    }

    private func makeSubscriptionsTab() -> UIViewController {
        let subs = RotatingNavigationController(
            rootViewController: SubscriptionsViewController(
                service: dependencies.feedService,
                channelViewControllerFactory:
                    dependencies.makeChannelViewController
            )
        )
        subs.tabBarItem = UITabBarItem(
            title: "Subscriptions",
            image: TabBarIcons.subscriptions(),
            tag: 1
        )
        return subs
    }

    private func makeLibraryTab() -> UIViewController {
        let library = RotatingNavigationController(
            rootViewController: LibraryViewController(
                dependencies: dependencies
            )
        )
        library.tabBarItem = UITabBarItem(
            title: "Library",
            image: TabBarIcons.library(),
            tag: 2
        )
        return library
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
        miniPlayerBar?.applyTheme()
    }

    func installPlayerPanel(_ panel: PlayerPanelViewController) {
        if let existing = playerPanel {
            removePlayerPanel(existing)
        }
        addChild(panel)
        panel.view.frame = view.bounds
        panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(panel.view, aboveSubview: tabBar)
        panel.didMove(toParent: self)
        playerPanel = panel

        miniPlayerBar?.removeFromSuperview()
        let bar = MiniPlayerBar()
        view.addSubview(bar)
        // PiP: fixed width = screen / 3, anchored bottom-right
        let pipWidth = max(160, view.bounds.width / 3)
        // Use safeAreaLayoutGuide to avoid cross-hierarchy constraint crash
        // (tabBar.topAnchor can be in a different hierarchy on some iOS 12 paths)
        let bottomConstraint = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.widthAnchor.constraint(equalToConstant: pipWidth),
            bottomConstraint
        ])
        bar.isHidden = true
        bar.alpha = 0
        miniPlayerBar = bar
        miniPlayerBarBottomConstraint = bottomConstraint

        panel.miniBar = bar
        panel.view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        panel.expand(animated: true)
    }

    func removePlayerPanel(_ panel: PlayerPanelViewController) {
        if playerPanel === panel {
            playerPanel = nil
        }
        miniPlayerBar?.removeFromSuperview()
        miniPlayerBar = nil
        miniPlayerBarBottomConstraint = nil
        panel.willMove(toParent: nil)
        panel.view.removeFromSuperview()
        panel.removeFromParent()
    }
}
