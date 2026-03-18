import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ThemeManager.shared.applyGlobal()
        window = UIWindow(frame: UIScreen.main.bounds)

        if OAuthClient.shared.isSignedIn {
            window?.rootViewController = MainTabBarController()
        } else {
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                self?.window?.rootViewController = MainTabBarController()
            }
            window?.rootViewController = auth
        }

        window?.makeKeyAndVisible()

        NotificationCenter.default.addObserver(self, selector: #selector(showAuth),
                                               name: .authorizationRequired, object: nil)
        return true
    }

    @objc private func showAuth() {
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.rootViewController,
                  !(root is AuthViewController),
                  root.presentedViewController == nil
            else { return }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                root.dismiss(animated: true)
                // Reload data in all tabs by replacing root
                self?.window?.rootViewController = MainTabBarController()
            }
            root.present(auth, animated: true)
        }
    }
}
