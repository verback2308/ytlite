import UIKit

// Full-screen settings page for SponsorBlock.
// swiftlint:disable:next type_name
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
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissTapped)
        )
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func setupTableView() {
        tableView.register(
            SBCategoryCell.self,
            forCellReuseIdentifier: SBCategoryCell.reuseID
        )
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
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor       = theme.background
        tableView.backgroundColor  = theme.background
        tableView.separatorColor   = theme.separator
        tableView.reloadData()
    }

    @objc
    private func dismissTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SponsorBlockSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        categories.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        "Segment Categories"
    }

    func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        SponsorBlockService.attributionText
    }

    func tableView(
        _ tableView: UITableView,
        willDisplayHeaderView view: UIView,
        forSection section: Int
    ) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor =
            ThemeManager.shared.secondaryText
    }

    func tableView(
        _ tableView: UITableView,
        willDisplayFooterView view: UIView,
        forSection section: Int
    ) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor =
            ThemeManager.shared.secondaryText
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let category = categories[indexPath.row]
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SBCategoryCell.reuseID,
            for: indexPath
        ) as? SBCategoryCell else {
            return UITableViewCell()
        }
        cell.configure(category: category)
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        showBehaviorPicker(
            for: categories[indexPath.row],
            at: indexPath
        )
    }

    private func showBehaviorPicker(
        for category: SBCategory,
        at indexPath: IndexPath
    ) {
        let options = SBSkipBehavior.options(for: category)
        let current = SponsorBlockService.skipBehavior(for: category)
        let sheet = UIAlertController(
            title: category.displayName,
            message: nil,
            preferredStyle: .actionSheet
        )
        for behavior in options {
            sheet.addAction(
                makeBehaviorAction(
                    behavior,
                    current: current,
                    category: category,
                    indexPath: indexPath
                )
            )
        }
        sheet.addAction(
            UIAlertAction(title: "取消", style: .cancel)
        )
        configurePopover(sheet, at: indexPath)
        present(sheet, animated: true)
    }

    private func makeBehaviorAction(
        _ behavior: SBSkipBehavior,
        current: SBSkipBehavior,
        category: SBCategory,
        indexPath: IndexPath
    ) -> UIAlertAction {
        let action = UIAlertAction(
            title: behavior.displayName,
            style: .default
        ) { [weak self] _ in
            SponsorBlockService.setSkipBehavior(behavior, for: category)
            self?.tableView.reloadRows(at: [indexPath], with: .none)
        }
        if behavior == current {
            action.setValue(true, forKey: "checked")
        }
        return action
    }

    private func configurePopover(
        _ sheet: UIAlertController,
        at indexPath: IndexPath
    ) {
        guard let pop = sheet.popoverPresentationController else {
            return
        }
        let cell = tableView.cellForRow(at: indexPath)
        pop.sourceView = cell ?? view
        pop.sourceRect = cell?.bounds ?? view.bounds
        pop.permittedArrowDirections = [.up, .down]
    }
}
