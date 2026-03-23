import UIKit

final class SplashViewController: UIViewController {

    var onComplete: (() -> Void)?

    private let logoView = UIImageView()
    private let appNameLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateAndComplete()
    }

    // MARK: - UI

    private func setupUI() {
        // Use the app icon from Assets
        logoView.image = UIImage(named: "Logo")
        logoView.contentMode = .scaleAspectFit
        logoView.layer.cornerRadius = 20
        logoView.layer.masksToBounds = true
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.alpha = 0
        view.addSubview(logoView)

        appNameLabel.text = "YTVLite"
        appNameLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        appNameLabel.textColor = .white
        appNameLabel.textAlignment = .center
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        appNameLabel.alpha = 0
        view.addSubview(appNameLabel)

        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            logoView.widthAnchor.constraint(equalToConstant: 100),
            logoView.heightAnchor.constraint(equalToConstant: 100),

            appNameLabel.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 20),
            appNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Animation

    private func animateAndComplete() {
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            self.logoView.alpha = 1
            self.appNameLabel.alpha = 1
            self.logoView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        } completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.logoView.transform = .identity
            } completion: { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    UIView.animate(withDuration: 0.3) {
                        self.logoView.alpha = 0
                        self.appNameLabel.alpha = 0
                    } completion: { _ in
                        self.onComplete?()
                    }
                }
            }
        }
    }
}
