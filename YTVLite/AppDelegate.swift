import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ThemeManager.shared.applyGlobal()
        BackgroundPlaybackService.apply()
        if ReturnYouTubeDislikeService.enabled {
            ReturnYouTubeDislikeService.shared.prepareIfNeeded()
        }
        window = UIWindow(frame: UIScreen.main.bounds)

        let splash = SplashViewController()
        splash.onComplete = { [weak self] in
            if OAuthClient.shared.isSignedIn {
                UserProfileStore.shared.load()
                self?.showMain()
            } else if OAuthClient.shared.isAnonymous {
                self?.showMain()
            } else {
                self?.showAuth()
            }
        }
        window?.rootViewController = splash
        window?.makeKeyAndVisible()

        NotificationCenter.default.addObserver(self, selector: #selector(handleAuthRequired),
                                               name: .authorizationRequired, object: nil)
        return true
    }

    func showMain() {
        window?.rootViewController = MainTabBarController()
    }

    @objc private func handleAuthRequired() {
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.rootViewController,
                  !(root is AuthViewController),
                  !(root is SplashViewController),
                  root.presentedViewController == nil
            else { return }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                root.dismiss(animated: true)
                UserProfileStore.shared.load()
                self?.window?.rootViewController = MainTabBarController()
            }
            auth.onContinueAnonymously = { [weak self] in
                root.dismiss(animated: true)
                self?.showMain()
            }
            root.present(auth, animated: true)
        }
    }
}
