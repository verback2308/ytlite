import UIKit

class MainTabBarController: UITabBarController {
    private let dependencies: AppDependencies
    private weak var playerPanel: PlayerPanelViewController?
    private var miniPlayerBar: MiniPlayerBar?
    private var miniPlayerBarBottomConstraint: NSLayoutConstraint?

    override var childForStatusBarHidden: UIViewController? {
        playerPanel ?? selectedViewController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        playerPanel ?? selectedViewController
    }

    override var shouldAutorotate: Bool {
        if UIDevice.current.userInterfaceIdiom != .pad {
            return false
        }
        return selectedViewController?.shouldAutorotate ?? super.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom != .pad {
            return .portrait
        }
        return selectedViewController?.supportedInterfaceOrientations
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

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.tabBar.setNeedsLayout()
            },
            completion: { [weak self] _ in
                self?.tabBar.setNeedsLayout()
                self?.tabBar.layoutIfNeeded()
            }
        )
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
            rootViewController:
                dependencies.makeSubscriptionsViewController()
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
        // Use a proportional width (1/3 of the parent) so the bar stays correctly
        // sized after device rotation without needing to recreate the constraint.
        let bottomConstraint = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1.0 / 3.0),
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
        // Defer the tab-bar re-layout to the next run-loop cycle so UIKit
        // finishes all internal hierarchy cleanup before we force a layout.
        // Without this, item positions can be stale after a
        // landscape → fullscreen → portrait → close sequence.
        DispatchQueue.main.async { [weak self] in
            self?.tabBar.setNeedsLayout()
            self?.tabBar.layoutIfNeeded()
        }
    }
}
