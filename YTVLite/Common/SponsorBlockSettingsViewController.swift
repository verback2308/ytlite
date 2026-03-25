import UIKit

/// Full-screen settings page for SponsorBlock.
/// Shows a row per segment category with a color swatch, skip-behavior picker, and description.
final class SponsorBlockSettingsViewController: UIViewController {

    private lazy var tableView: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()

    private let categories = SBCategory.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SponsorBlock"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissTapped))
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification, object: nil)
    }

    private func setupTableView() {
        tableView.register(SBCategoryCell.self, forCellReuseIdentifier: SBCategoryCell.reuseID)
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.rowHeight  = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor       = t.background
        tableView.backgroundColor  = t.background
        tableView.separatorColor   = t.separator
        tableView.reloadData()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SponsorBlockSettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        categories.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Segment Categories"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        SponsorBlockService.attributionText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let category = categories[indexPath.row]
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SBCategoryCell.reuseID, for: indexPath) as! SBCategoryCell
        cell.configure(category: category)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showBehaviorPicker(for: categories[indexPath.row], at: indexPath)
    }

    private func showBehaviorPicker(for category: SBCategory, at indexPath: IndexPath) {
        let options  = SBSkipBehavior.options(for: category)
        let current  = SponsorBlockService.skipBehavior(for: category)
        let sheet    = UIAlertController(title: category.displayName,
                                         message: nil, preferredStyle: .actionSheet)
        for behavior in options {
            let action = UIAlertAction(title: behavior.displayName, style: .default) { [weak self] _ in
                SponsorBlockService.setSkipBehavior(behavior, for: category)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            if behavior == current { action.setValue(true, forKey: "checked") }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = sheet.popoverPresentationController {
            let cell = tableView.cellForRow(at: indexPath) ?? view
            pop.sourceView = cell
            pop.sourceRect = cell!.bounds
            pop.permittedArrowDirections = [.up, .down]
        }
        present(sheet, animated: true)
    }
}

// MARK: - SBCategoryCell

private final class SBCategoryCell: UITableViewCell {

    static let reuseID = "SBCategoryCell"

    private let nameLabel     = UILabel()
    private let descLabel     = UILabel()
    private let behaviorLabel = UILabel()
    private let colorSwatch   = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        nameLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        descLabel.font = UIFont.systemFont(ofSize: 12)
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        behaviorLabel.font = UIFont.systemFont(ofSize: 13)
        behaviorLabel.textAlignment = .right
        behaviorLabel.setContentHuggingPriority(.required, for: .horizontal)
        behaviorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        behaviorLabel.translatesAutoresizingMaskIntoConstraints = false

        colorSwatch.layer.cornerRadius = 3
        colorSwatch.layer.borderWidth  = 0.5
        colorSwatch.layer.borderColor  = UIColor.white.withAlphaComponent(0.3).cgColor
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(nameLabel)
        contentView.addSubview(descLabel)
        contentView.addSubview(behaviorLabel)
        contentView.addSubview(colorSwatch)

        NSLayoutConstraint.activate([
            // Color swatch — trailing, vertically centred with name
            colorSwatch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            colorSwatch.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 40),
            colorSwatch.heightAnchor.constraint(equalToConstant: 16),

            // Behavior label — left of swatch
            behaviorLabel.trailingAnchor.constraint(equalTo: colorSwatch.leadingAnchor, constant: -8),
            behaviorLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            // Name label — top, left
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: behaviorLabel.leadingAnchor, constant: -8),

            // Description — below name, full width
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            descLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        accessoryType = .disclosureIndicator
    }

    func configure(category: SBCategory) {
        let t = ThemeManager.shared
        backgroundColor       = t.surface
        nameLabel.textColor   = t.primaryText
        descLabel.textColor   = t.secondaryText
        behaviorLabel.textColor = t.secondaryText

        nameLabel.text     = category.displayName
        descLabel.text     = category.categoryDescription
        colorSwatch.backgroundColor = category.seekBarColor
        behaviorLabel.text = SponsorBlockService.skipBehavior(for: category).displayName
    }
}
