import UIKit

private func resized(_ name: String, size: CGFloat) -> UIImage? {
    guard let img = UIImage(named: name) else { return nil }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
        img.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }.withRenderingMode(.alwaysTemplate)
}

/// Builds and manages the shared navigation bar buttons (Search + Settings + Profile/Avatar).
/// Call `install(in:)` from any UIViewController that needs them.
final class ToolbarManager {

    static let shared = ToolbarManager()
    private init() {}

    // MARK: - Install buttons in a view controller

    func install(in vc: UIViewController) {
        let searchBtn = UIBarButtonItem(
            image: resized("icon_Magnifyingglass", size: 22),
            style: .plain, target: vc,
            action: #selector(UIViewController.toolbarOpenSearch))

        let settingsBtn = UIBarButtonItem(
            image: resized("icon_Gear", size: 22),
            style: .plain, target: vc,
            action: #selector(UIViewController.toolbarOpenSettings))

        let profileBtn = makeProfileButton(target: vc,
                                           action: #selector(UIViewController.toolbarOpenProfile))

        vc.navigationItem.rightBarButtonItems = [profileBtn, settingsBtn, searchBtn]
        NotificationCenter.default.addObserver(
            vc,
            selector: #selector(UIViewController.toolbarRefreshProfileButton),
            name: UserProfileStore.didUpdateNotification,
            object: nil)
    }

    private func makeProfileButton(target: AnyObject, action: Selector) -> UIBarButtonItem {
        let button = ProfileAvatarButton()
        button.refresh()
        button.addTarget(target, action: action, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }
}

// MARK: - UIViewController extension for toolbar actions

extension UIViewController {

    @objc func toolbarOpenSearch() {
        navigationController?.pushViewController(SearchViewController(), animated: true)
    }

    @objc func toolbarOpenSettings() {
        let nav = UINavigationController(rootViewController: SettingsViewController())
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    @objc func toolbarOpenProfile() {
        if OAuthClient.shared.isSignedIn {
            let name = UserProfileStore.shared.displayName ?? "Account"
            let sheet = UIAlertController(title: name, message: nil,
                                          preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
                OAuthClient.shared.signOut()
                UserProfileStore.shared.clear()
                (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            configurePopover(sheet)
            present(sheet, animated: true)
        } else {
            let sheet = UIAlertController(title: "Not signed in", message: nil,
                                          preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Sign In", style: .default) { _ in
                (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            configurePopover(sheet)
            present(sheet, animated: true)
        }
    }

    @objc func toolbarRefreshProfileButton() {
        for item in navigationItem.rightBarButtonItems ?? [] {
            (item.customView as? ProfileAvatarButton)?.refresh()
        }
    }

    private func configurePopover(_ alert: UIAlertController) {
        if let pop = alert.popoverPresentationController {
            // Anchor to the profile button if found, otherwise to the view
            if let btn = navigationItem.rightBarButtonItems?.first(where: {
                $0.customView is ProfileAvatarButton
            }) {
                pop.barButtonItem = btn
            } else {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY,
                                        width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
        }
    }
}

// MARK: - AppDelegate helpers

extension AppDelegate {
    @objc func showAuth() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                UserProfileStore.shared.load()
                self?.showMain()
            }
            auth.onContinueAnonymously = { [weak self] in
                self?.showMain()
            }
            if let presented = window.rootViewController?.presentedViewController {
                presented.dismiss(animated: false) { window.rootViewController = auth }
            } else {
                window.rootViewController = auth
            }
        }
    }
}

// MARK: - Profile Avatar Button

final class ProfileAvatarButton: UIButton {

    private let size: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        layer.cornerRadius = size / 2
        clipsToBounds = true
        contentMode = .scaleAspectFill
        imageView?.contentMode = .scaleAspectFill
        setImage(defaultImage(), for: .normal)
        tintColor = ThemeManager.shared.isDark ? .white : .darkGray
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        if let avatar = UserProfileStore.shared.avatarImage {
            setImage(avatar, for: .normal)
        } else {
            setImage(defaultImage(), for: .normal)
            tintColor = ThemeManager.shared.isDark ? .white : .darkGray
        }
    }

    private func defaultImage() -> UIImage? {
        if #available(iOS 13, *) {
            return UIImage(systemName: "person.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: size, weight: .light))
        }
        return nil
    }
}
