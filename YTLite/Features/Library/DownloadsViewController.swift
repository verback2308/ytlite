import UIKit

final class DownloadsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloads"
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        setupUI()
    }

    private func setupUI() {
        let iconView: UIView
        if #available(iOS 13, *) {
            let iv = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
            iv.tintColor = .lightGray
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            iconView = iv
        } else {
            let iv = UIView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iconView = iv
        }

        let label = UILabel()
        label.text = "Downloads coming soon"
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 15)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconView)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc
    private func applyTheme() {
        view.backgroundColor = ThemeManager.shared.background
    }
}
