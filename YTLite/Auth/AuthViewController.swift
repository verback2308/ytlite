import UIKit
import SafariServices

final class AuthViewController: UIViewController {
    var onAuthorized: (() -> Void)?
    var onContinueAnonymously: (() -> Void)?

    private let titleLabel = UILabel()
    private let instructionLabel = UILabel()
    private let codeLabel = UILabel()
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let anonymousButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .white)

    private var verificationURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        startAuth()
    }

    private func setupUI() {
        configureLabels()
        configureButtons()
        configureSpinner()
        addControlSubviews()
        layoutTitleAndCode()
        layoutButtonsAndStatus()
    }

    @objc
    private func openVerificationURL() {
        guard let url = verificationURL else {
            return
        }
        UIPasteboard.general.string = codeLabel.text
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    @objc
    private func continueAnonymously() {
        OAuthClient.shared.isAnonymous = true
        if let cb = onContinueAnonymously {
            cb()
        } else {
            onAuthorized?()
        }
    }
}

// MARK: - Configuration
private extension AuthViewController {
    func configureLabels() {
        titleLabel.text = "Sign in to YouTube"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center

        instructionLabel.text = "Tap the button below,"
            + " then paste your code on the page that opens."
        instructionLabel.textColor = .lightGray
        instructionLabel.font = UIFont.systemFont(ofSize: 15)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        codeLabel.textColor = .white
        codeLabel.font = UIFont(
            name: "Menlo-Bold",
            size: 36
        ) ?? UIFont.boldSystemFont(ofSize: 36)
        codeLabel.textAlignment = .center

        statusLabel.text = "Fetching code..."
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
    }

    func configureButtons() {
        configureOpenButton()
        configureAnonymousButton()
    }

    func configureOpenButton() {
        openButton.setTitle(
            "Open google.com/device",
            for: .normal
        )
        openButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        openButton.backgroundColor = ThemeManager.shared.accent
        openButton.setTitleColor(.white, for: .normal)
        openButton.layer.cornerRadius = 10
        openButton.contentEdgeInsets = UIEdgeInsets(
            top: 14, left: 28, bottom: 14, right: 28
        )
        openButton.addTarget(
            self,
            action: #selector(openVerificationURL),
            for: .touchUpInside
        )
        openButton.isHidden = true
    }

    func configureAnonymousButton() {
        anonymousButton.setTitle(
            "Continue Anonymously",
            for: .normal
        )
        anonymousButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        anonymousButton.setTitleColor(
            UIColor(white: 0.55, alpha: 1),
            for: .normal
        )
        anonymousButton.addTarget(
            self,
            action: #selector(continueAnonymously),
            for: .touchUpInside
        )
    }

    func configureSpinner() {
        spinner.hidesWhenStopped = true
        spinner.startAnimating()
    }

    func addControlSubviews() {
        let views: [UIView] = [
            titleLabel, instructionLabel, codeLabel,
            openButton, statusLabel, spinner, anonymousButton
        ]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
    }
}

// MARK: - Layout
private extension AuthViewController {
    func layoutTitleAndCode() {
        let padding: CGFloat = 40
        layoutTitleConstraints(padding: padding)
        layoutInstructionConstraints(padding: padding)
    }

    func layoutTitleConstraints(padding: CGFloat) {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 80
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: padding
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -padding
            ),
            codeLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            codeLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 48
            )
        ])
    }

    func layoutInstructionConstraints(padding: CGFloat) {
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            instructionLabel.topAnchor.constraint(
                equalTo: codeLabel.bottomAnchor,
                constant: 20
            ),
            instructionLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: padding
            ),
            instructionLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -padding
            )
        ])
    }

    func layoutButtonsAndStatus() {
        let padding: CGFloat = 40
        layoutOpenAndStatusConstraints(padding: padding)
        layoutBottomConstraints()
    }

    func layoutOpenAndStatusConstraints(padding: CGFloat) {
        NSLayoutConstraint.activate([
            openButton.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            openButton.topAnchor.constraint(
                equalTo: instructionLabel.bottomAnchor,
                constant: 32
            ),
            statusLabel.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            statusLabel.topAnchor.constraint(
                equalTo: openButton.bottomAnchor,
                constant: 32
            ),
            statusLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: padding
            ),
            statusLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -padding
            )
        ])
    }

    func layoutBottomConstraints() {
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            spinner.topAnchor.constraint(
                equalTo: statusLabel.bottomAnchor,
                constant: 16
            ),
            anonymousButton.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            anonymousButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -28
            )
        ])
    }
}

// MARK: - Auth Flow
private extension AuthViewController {
    func startAuth() {
        OAuthClient.shared.requestDeviceCode { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self?.statusLabel.text =
                        "Error: \(error.localizedDescription)"
                    self?.spinner.stopAnimating()
                case .success(let code):
                    self?.handleDeviceCode(code)
                }
            }
        }
    }

    func handleDeviceCode(_ code: OAuthClient.DeviceCodeResponse) {
        codeLabel.text = code.userCode
        verificationURL = URL(string: code.verificationURL)
        openButton.isHidden = false
        statusLabel.text = "Waiting for authorization..."

        let config = OAuthClient.PollConfig(
            deviceCode: code.deviceCode,
            clientId: code.clientId,
            clientSecret: code.clientSecret,
            interval: code.interval
        )
        OAuthClient.shared.pollForToken(
            config: config
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    OAuthClient.shared.isAnonymous = false
                    UserProfileStore.shared.load()
                    self?.onAuthorized?()
                case .failure(let error):
                    self?.statusLabel.text =
                        "Failed: \(error.localizedDescription)"
                    self?.spinner.stopAnimating()
                }
            }
        }
    }
}
