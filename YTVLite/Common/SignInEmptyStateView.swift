import UIKit

/// Reusable "sign in" empty state: icon + message + red Sign In button.
final class SignInEmptyStateView: UIView {
    var onSignIn: (() -> Void)?

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .lightGray
        iv.translatesAutoresizingMaskIntoConstraints = false
        if let asset = UIImage(named: "icon_person_fill") {
            iv.image = asset  // template rendering set in asset catalog
        } else if #available(iOS 13, *) {
            iv.image = UIImage(systemName: "person.circle")
        }
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let signInButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Sign In", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        btn.backgroundColor = ThemeManager.shared.accent
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 20
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 32, bottom: 10, right: 32)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = message
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(signInButton)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            signInButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            signInButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            signInButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    @objc
    private func signInTapped() {
        onSignIn?()
    }
}
