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
        case theme, quality, backgroundPlayback, persistCache, clearCache, rydEnabled
        case sponsorBlockEnabled, sponsorBlockSettings
    }

    private var sections: [(header: String?, footer: String?, rows: [Row])] {
        var sponsorBlockRows: [Row] = [.sponsorBlockEnabled]
        if SponsorBlockService.enabled { sponsorBlockRows.append(.sponsorBlockSettings) }

        return [
            ("Theme",    nil, [.theme]),
            ("Playback", nil, [.quality, .backgroundPlayback]),
            ("Cache",    nil, [.persistCache, .clearCache]),
            ("Return YouTube Dislike",
             "Dislike counts are powered by Return YouTube Dislike (returnyoutubedislike.com) — an open community project.",
             [.rydEnabled]),
            ("SponsorBlock",
             SponsorBlockService.enabled ? SponsorBlockService.attributionText : nil,
             sponsorBlockRows),
        ]
    }

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

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .theme:
            return makeThemeCell()
        case .quality:
            return makeDisclosureCell("Default Quality", value: VideoQualityStore.displayName)
        case .backgroundPlayback:
            return makeToggleCell("Background Playback", isOn: BackgroundPlaybackService.isEnabled) { isOn in
                BackgroundPlaybackService.isEnabled = isOn
                BackgroundPlaybackService.apply()
            }
        case .persistCache:
            return makeToggleCell("Keep feed cache 24h", isOn: AppCache.persistenceEnabled) {
                AppCache.persistenceEnabled = $0
            }
        case .clearCache:
            return makeDestructiveCell("Clear All Cache")
        case .rydEnabled:
            return makeToggleCell("Return YouTube Dislike", isOn: ReturnYouTubeDislikeService.enabled) {
                ReturnYouTubeDislikeService.enabled = $0
            }
        case .sponsorBlockEnabled:
            return makeToggleCell("SponsorBlock", isOn: SponsorBlockService.enabled) { [weak self] isOn in
                SponsorBlockService.enabled = isOn
                self?.reloadSponsorBlockSection()
            }
        case .sponsorBlockSettings:
            return makeDisclosureCell("SponsorBlock Settings")
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .quality:              showQualityPicker()
        case .clearCache:           clearCache()
        case .sponsorBlockSettings: showSponsorBlockSettings()
        default: break
        }
    }

    // MARK: - Cell factories

    private func makeToggleCell(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> UITableViewCell {
        let cell = ToggleCell()
        cell.configure(title: title, isOn: isOn)
        cell.onToggle = onChange
        return cell
    }

    private func makeDisclosureCell(_ title: String, value: String? = nil) -> UITableViewCell {
        let t    = ThemeManager.shared
        let cell = UITableViewCell(style: value != nil ? .value1 : .default, reuseIdentifier: nil)
        cell.textLabel?.text            = title
        cell.textLabel?.textColor       = t.primaryText
        cell.detailTextLabel?.text      = value
        cell.detailTextLabel?.textColor = t.secondaryText
        cell.backgroundColor            = t.surface
        cell.accessoryType              = .disclosureIndicator
        return cell
    }

    private func makeDestructiveCell(_ title: String) -> UITableViewCell {
        let t    = ThemeManager.shared
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text      = title
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.backgroundColor      = t.surface
        return cell
    }

    private func makeThemeCell() -> UITableViewCell {
        let t    = ThemeManager.shared
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text      = "Theme"
        cell.textLabel?.textColor = t.primaryText
        cell.backgroundColor      = t.surface
        cell.selectionStyle       = .none

        let seg = UISegmentedControl(items: ["Dark", "Light", "Auto"])
        switch t.themeMode {
        case .dark:  seg.selectedSegmentIndex = 0
        case .light: seg.selectedSegmentIndex = 1
        case .auto:  seg.selectedSegmentIndex = 2
        }
        seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
        cell.accessoryView = seg
        return cell
    }

    // MARK: - Actions

    private func reloadSponsorBlockSection() {
        if let idx = sections.firstIndex(where: { $0.header == "SponsorBlock" }) {
            tableView.reloadSections(IndexSet(integer: idx), with: .automatic)
        }
    }

    private func showSponsorBlockSettings() {
        let vc  = SponsorBlockSettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

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
        AppCache.shared.clearAllDiskCache()
        let alert = UIAlertController(title: "Cache Cleared",
                                      message: "Image and feed cache has been cleared.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - ToggleCell
// Reusable cell with a UISwitch that fires a closure — avoids target/selector boilerplate.

private final class ToggleCell: UITableViewCell {

    var onToggle: ((Bool) -> Void)?

    private let toggle = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        toggle.addTarget(self, action: #selector(handleToggle), for: .valueChanged)
        accessoryView = toggle
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, isOn: Bool) {
        let t = ThemeManager.shared
        textLabel?.text      = title
        textLabel?.textColor = t.primaryText
        backgroundColor      = t.surface
        toggle.isOn          = isOn
    }

    @objc private func handleToggle() { onToggle?(toggle.isOn) }
}

// MARK: - VideoQualityStore

enum VideoQualityStore {
    static let options = ["Auto", "1080p", "720p", "480p", "360p"]

    static var selected: String {
        get { UserDefaults.standard.string(forKey: UserDefaultsKeys.VideoQuality.selected) ?? "Auto" }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.VideoQuality.selected) }
    }

    static var displayName: String { selected }

    /// Returns the maximum height in pixels for the selected quality, or nil for Auto.
    static var maxHeight: Int? {
        switch selected {
        case "1080p": return 1080
        case "720p":  return 720
        case "480p":  return 480
        case "360p":  return 360
        default:      return nil
        }
    }
}
