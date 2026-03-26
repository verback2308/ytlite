import UIKit

final class ChannelAboutViewController: UIViewController {
    private let page: ChannelPage
    private let theme = ThemeManager.shared

    init(page: ChannelPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        title = "About"
        if #available(iOS 13, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close, target: self, action: #selector(dismissSelf))
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Close", style: .done, target: self, action: #selector(dismissSelf))
        }
        setupUI()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.backgroundColor = theme.background
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        // Stats row: subscribers + videos
        let statsStack = UIStackView()
        statsStack.axis = .horizontal
        statsStack.spacing = 24
        statsStack.distribution = .fillEqually

        if let subs = page.info.subscriberCountText {
            statsStack.addArrangedSubview(makeStatView(value: subs, label: "Subscribers"))
        }
        if let vids = page.info.videoCountText {
            let count = vids
                .replacingOccurrences(of: " videos", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " video", with: "", options: .caseInsensitive)
            statsStack.addArrangedSubview(makeStatView(value: count, label: "Videos"))
        }
        if statsStack.arrangedSubviews.count > 0 {
            stack.addArrangedSubview(statsStack)
            addSeparator(to: stack)
        }

        // Description
        if let desc = page.info.description, !desc.isEmpty {
            stack.addArrangedSubview(makeLabel(text: "Description", style: .subheadline, color: theme.secondaryText))
            let descLabel = makeLabel(text: desc, style: .body, color: theme.primaryText)
            descLabel.numberOfLines = 0
            stack.addArrangedSubview(descLabel)
            addSeparator(to: stack)
        }

        // Contact
        if let contact = page.info.contactInfo, !contact.isEmpty {
            stack.addArrangedSubview(makeLabel(text: "Contact", style: .subheadline, color: theme.secondaryText))
            let btn = UIButton(type: .system)
            btn.setTitle(contact, for: .normal)
            btn.contentHorizontalAlignment = .leading
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 15)
            btn.addTarget(self, action: #selector(contactTapped), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
    }

    @objc private func contactTapped() {
        guard let contact = page.info.contactInfo else { return }
        let urlStr: String
        if contact.contains("@") && !contact.hasPrefix("http") {
            urlStr = "mailto:\(contact)"
        } else if contact.hasPrefix("http") {
            urlStr = contact
        } else {
            urlStr = "https://\(contact)"
        }
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private func makeStatView(value: String, label: String) -> UIView {
        let v = UIView()
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.boldSystemFont(ofSize: 20)
        valueLabel.textColor = theme.primaryText
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = UIFont.systemFont(ofSize: 12)
        nameLabel.textColor = theme.secondaryText
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(valueLabel)
        v.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: v.topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        return v
    }

    private func makeLabel(text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.preferredFont(forTextStyle: style)
        l.textColor = color
        l.numberOfLines = 1
        return l
    }

    private func addSeparator(to stack: UIStackView) {
        let sep = UIView()
        sep.backgroundColor = theme.separator
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(sep)
    }
}
