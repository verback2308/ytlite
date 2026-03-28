import UIKit

private func resized(_ name: String, size: CGFloat) -> UIImage? {
    guard let img = UIImage(named: name) else {
        return nil
    }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
        img.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }
    .withRenderingMode(.alwaysTemplate)
}

/// Builds and manages the shared navigation bar buttons (Search + Settings + Profile/Avatar).
/// Call `install(in:)` from any UIViewController that needs them.
final class ToolbarManager {
    static let shared = ToolbarManager()

    var searchViewControllerFactory: (() -> SearchViewController)?

    private init() {}

    // MARK: - Install buttons in a view controller

    func install(in vc: UIViewController) {
        let searchBtn = UIBarButtonItem(
            image: resized("icon_Magnifyingglass", size: 22),
            style: .plain,
            target: vc,
            action: #selector(UIViewController.toolbarOpenSearch)
        )

        let settingsBtn = UIBarButtonItem(
            image: resized("icon_Gear", size: 22),
            style: .plain,
            target: vc,
            action: #selector(UIViewController.toolbarOpenSettings)
        )

        let profileBtn = makeProfileButton(
            target: vc,
            action: #selector(UIViewController.toolbarOpenProfile)
        )

        vc.navigationItem.rightBarButtonItems = [profileBtn, settingsBtn, searchBtn]
        NotificationCenter.default.addObserver(
            vc,
            selector: #selector(UIViewController.toolbarRefreshProfileButton),
            name: UserProfileStore.didUpdateNotification,
            object: nil
        )
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
    @objc
    func toolbarOpenSearch() {
        let searchVC = ToolbarManager.shared.searchViewControllerFactory?()
        guard let searchVC else {
            assertionFailure("ToolbarManager search factory is not configured")
            return
        }
        navigationController?.pushViewController(searchVC, animated: true)
    }

    @objc
    func toolbarOpenSettings() {
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

    @objc
    func toolbarOpenProfile() {
        if OAuthClient.shared.isSignedIn {
            showSignedInSheet()
        } else {
            showSignedOutSheet()
        }
    }

    private func showSignedInSheet() {
        let name = UserProfileStore.shared.displayName ?? "Account"
        let sheet = UIAlertController(
            title: name,
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: "Sign Out",
            style: .destructive
        ) { _ in
            OAuthClient.shared.signOut()
            UserProfileStore.shared.clear()
            AppCache.shared.clearHomeFeed()
            NotificationCenter.default.post(
                name: .userDidSignOut,
                object: nil
            )
            (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopover(sheet)
        present(sheet, animated: true)
    }

    private func showSignedOutSheet() {
        let sheet = UIAlertController(
            title: "Not signed in",
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: "Sign In",
            style: .default
        ) { _ in
            (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        configurePopover(sheet)
        present(sheet, animated: true)
    }

    @objc
    func toolbarRefreshProfileButton() {
        for item in navigationItem.rightBarButtonItems ?? [] {
            (item.customView as? ProfileAvatarButton)?.refresh()
        }
    }

    private func configurePopover(_ alert: UIAlertController) {
        if let pop = alert.popoverPresentationController {
            if let btn = navigationItem.rightBarButtonItems?.first(where: {
                $0.customView is ProfileAvatarButton
            }) {
                pop.barButtonItem = btn
            } else {
                pop.sourceView = view
                pop.sourceRect = CGRect(
                    x: view.bounds.midX,
                    y: view.bounds.midY,
                    width: 0,
                    height: 0
                )
                pop.permittedArrowDirections = []
            }
        }
    }
}

// MARK: - AppDelegate helpers

extension AppDelegate {
    @objc
    func showAuth() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else {
                return
            }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                UserProfileStore.shared.load()
                self?.showMain()
            }
            auth.onContinueAnonymously = { [weak self] in
                self?.showMain()
            }
            if let presented = window.rootViewController?.presentedViewController {
                presented.dismiss(animated: false) {
                    window.rootViewController = auth
                }
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        tintColor = ThemeManager.shared.isDark ? .white : .darkGray
        if let avatar = UserProfileStore.shared.avatarImage {
            setImage(avatar, for: .normal)
        } else {
            setImage(defaultImage(), for: .normal)
        }
    }

    private func defaultImage() -> UIImage? {
        if let asset = UIImage(named: "icon_person_fill") {
            return asset
        }
        if #available(iOS 13, *) {
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .light)
            return UIImage(
                systemName: "person.circle.fill",
                withConfiguration: config
            )
        }
        let color = ThemeManager.shared.isDark ? UIColor.white : UIColor.darkGray
        return drawPersonPlaceholder(color: color)
    }

    private func drawPersonPlaceholder(color: UIColor) -> UIImage {
        let side = size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            color.setStroke()
            color.withAlphaComponent(0.25).setFill()
            cgCtx.setLineWidth(1.5)
            cgCtx.addEllipse(in: CGRect(x: 1, y: 1, width: side - 2, height: side - 2))
            cgCtx.drawPath(using: .fillStroke)
            color.setFill()
            let headR = side * 0.22
            let headRect = CGRect(
                x: side / 2 - headR,
                y: side * 0.2,
                width: headR * 2,
                height: headR * 2
            )
            cgCtx.fillEllipse(in: headRect)
            let bodyR = side * 0.32
            let bodyRect = CGRect(
                x: side / 2 - bodyR,
                y: side * 0.52,
                width: bodyR * 2,
                height: bodyR * 2
            )
            cgCtx.addEllipse(in: bodyRect)
            cgCtx.clip()
            cgCtx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
