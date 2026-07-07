import UIKit

/// The app-wide navigation controller: forwards rotation queries to the top
/// view controller and replaces the system back button on push with the
/// shared `NavChevron` button, so the chevron looks and sits the same on
/// every screen and iOS version.
final class RotatingNavigationController: UINavigationController {
    override var shouldAutorotate: Bool {
        topViewController?.shouldAutorotate ?? super.shouldAutorotate
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }
    override var prefersStatusBarHidden: Bool {
        topViewController?.prefersStatusBarHidden ?? super.prefersStatusBarHidden
    }
    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        topViewController?.prefersHomeIndicatorAutoHidden ?? super.prefersHomeIndicatorAutoHidden
    }
    override var childForHomeIndicatorAutoHidden: UIViewController? {
        topViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Replacing the system back button disables the edge-swipe pop
        // gesture; re-enable it (guarded so the root screen never pops).
        interactivePopGestureRecognizer?.delegate = self
        applyBarTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyBarTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    /// One bar configuration for every navigation bar in the app — bars
    /// with differing appearance setups use different item-layout metrics
    /// (visibly different chevron insets), so the bar styles itself here
    /// instead of per screen.
    @objc
    private func applyBarTheme() {
        let theme = ThemeManager.shared
        navigationBar.tintColor = theme.isDark ? .white : theme.accent
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = theme.surface
            appearance.titleTextAttributes = [.foregroundColor: theme.primaryText]
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
        } else {
            navigationBar.barTintColor = theme.surface
            navigationBar.isTranslucent = false
            navigationBar.barStyle = theme.barStyle
            navigationBar.titleTextAttributes = [.foregroundColor: theme.primaryText]
        }
    }

    override func pushViewController(
        _ viewController: UIViewController,
        animated: Bool
    ) {
        // `topViewController == nil` means this is the root being installed —
        // it gets no back button. Screens that manage their own left item
        // (e.g. the watch screen) are left alone.
        if topViewController != nil,
           viewController.navigationItem.leftBarButtonItem == nil {
            viewController.navigationItem.hidesBackButton = true
            viewController.navigationItem.leftBarButtonItem = NavChevron.barButton(
                kind: .back,
                target: self,
                action: #selector(popTapped)
            )
        }
        super.pushViewController(viewController, animated: animated)
    }

    @objc
    private func popTapped() {
        popViewController(animated: true)
    }
}

extension RotatingNavigationController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
