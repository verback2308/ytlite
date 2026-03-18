import UIKit
import SafariServices

final class AuthViewController: UIViewController {

    var onAuthorized: (() -> Void)?

    private let titleLabel = UILabel()
    private let instructionLabel = UILabel()
    private let codeLabel = UILabel()
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .white)

    private var verificationURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        startAuth()
    }

    private func setupUI() {
        titleLabel.text = "Sign in to YouTube"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center

        instructionLabel.text = "Your code has been copied to the clipboard.\nTap the button, paste it, and sign in."
        instructionLabel.textColor = .lightGray
        instructionLabel.font = UIFont.systemFont(ofSize: 15)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        codeLabel.textColor = .white
        codeLabel.font = UIFont(name: "Menlo-Bold", size: 36) ?? UIFont.boldSystemFont(ofSize: 36)
        codeLabel.textAlignment = .center

        openButton.setTitle("Open google.com/device", for: .normal)
        openButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        openButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        openButton.setTitleColor(.white, for: .normal)
        openButton.layer.cornerRadius = 10
        openButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28)
        openButton.addTarget(self, action: #selector(openVerificationURL), for: .touchUpInside)
        openButton.isHidden = true

        statusLabel.text = "Fetching code..."
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textAlignment = .center

        spinner.hidesWhenStopped = true
        spinner.startAnimating()

        let views: [UIView] = [titleLabel, instructionLabel, codeLabel, openButton, statusLabel, spinner]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let p: CGFloat = 40
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),

            codeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            codeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 48),

            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),

            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 32),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 32),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: p),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -p),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])
    }

    @objc private func openVerificationURL() {
        guard let url = verificationURL else { return }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func startAuth() {
        OAuthClient.shared.requestDeviceCode { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self?.statusLabel.text = "Error: \(error.localizedDescription)"
                    self?.spinner.stopAnimating()
                case .success(let code):
                    self?.codeLabel.text = code.userCode
                    self?.verificationURL = URL(string: code.verificationURL)
                    self?.openButton.isHidden = false
                    self?.statusLabel.text = "Waiting for authorization..."

                    // Copy code to clipboard and open the page automatically
                    UIPasteboard.general.string = code.userCode
                    if let url = URL(string: code.verificationURL) {
                        let safari = SFSafariViewController(url: url)
                        self?.present(safari, animated: true)
                    }

                    OAuthClient.shared.pollForToken(deviceCode: code.deviceCode,
                                                    clientId: code.clientId,
                                                    clientSecret: code.clientSecret,
                                                    interval: code.interval) { [weak self] result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                self?.onAuthorized?()
                            case .failure(let error):
                                self?.statusLabel.text = "Failed: \(error.localizedDescription)"
                                self?.spinner.stopAnimating()
                            }
                        }
                    }
                }
            }
        }
    }
}
