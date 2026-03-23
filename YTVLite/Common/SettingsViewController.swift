import UIKit

/// Settings popup presented as a sheet from the toolbar.
final class SettingsViewController: UIViewController {

    private lazy var tableView: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()

    private enum Row {
        case theme, quality, clearCache
    }

    private let sections: [(header: String?, rows: [Row])] = [
        ("Theme",   [.theme]),
        ("Playback",[.quality]),
        (nil,       [.clearCache]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismiss(_:)))
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate   = self
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
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        tableView.separatorColor  = t.separator
        tableView.reloadData()
    }

    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }
}

// MARK: - Data source / delegate

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let t   = ThemeManager.shared

        switch row {
        case .theme:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Theme"
            cell.textLabel?.textColor = t.primaryText
            cell.backgroundColor = t.surface
            cell.selectionStyle  = .none

            let seg = UISegmentedControl(items: ["Dark", "Light", "Auto"])
            switch t.themeMode {
            case .dark:  seg.selectedSegmentIndex = 0
            case .light: seg.selectedSegmentIndex = 1
            case .auto:  seg.selectedSegmentIndex = 2
            }
            seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
            cell.accessoryView = seg
            return cell

        case .quality:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text  = "Default Quality"
            cell.textLabel?.textColor = t.primaryText
            cell.detailTextLabel?.text = VideoQualityStore.displayName
            cell.detailTextLabel?.textColor = t.secondaryText
            cell.backgroundColor  = t.surface
            cell.accessoryType    = .disclosureIndicator
            return cell

        case .clearCache:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text  = "Clear Image Cache"
            cell.textLabel?.textColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            cell.textLabel?.textAlignment = .center
            cell.backgroundColor  = t.surface
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .quality: showQualityPicker()
        case .clearCache: clearCache()
        default: break
        }
    }

    // MARK: - Actions

    @objc private func themeChanged(_ seg: UISegmentedControl) {
        switch seg.selectedSegmentIndex {
        case 0: ThemeManager.shared.themeMode = .dark
        case 1: ThemeManager.shared.themeMode = .light
        default: ThemeManager.shared.themeMode = .auto
        }
    }

    private func showQualityPicker() {
        let options = VideoQualityStore.options
        let sheet = UIAlertController(title: "Default Quality", message: nil, preferredStyle: .actionSheet)
        options.forEach { opt in
            let action = UIAlertAction(title: opt, style: .default) { _ in
                VideoQualityStore.selected = opt
                self.tableView.reloadData()
            }
            if opt == VideoQualityStore.selected {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func clearCache() {
        ThumbnailImageView.clearCache()
        AppCache.shared.clearHomeFeed()
        AppCache.shared.clearSubscriptionsFeed()
        let alert = UIAlertController(title: "Cache Cleared",
                                      message: "Image and feed cache has been cleared.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - VideoQualityStore

enum VideoQualityStore {
    static let options = ["Auto", "1080p", "720p", "480p", "360p"]
    private static let key = "defaultVideoQuality"

    static var selected: String {
        get { UserDefaults.standard.string(forKey: key) ?? "Auto" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var displayName: String { selected }

    /// Returns the maximum height in pixels for the selected quality, or nil for Auto.
    static var maxHeight: Int? {
        switch selected {
        case "1080p": return 1080
        case "720p":  return 720
        case "480p":  return 480
        case "360p":  return 360
        default:      return nil   // Auto
        }
    }
}
