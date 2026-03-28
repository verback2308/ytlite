import UIKit

/// Settings popup presented as a sheet from the toolbar.
final class SettingsViewController: UIViewController {
    private enum Row {
        case theme, quality, backgroundPlayback, persistCache, clearCache, rydEnabled
        case sponsorBlockEnabled, sponsorBlockSettings
    }
    private struct Section {
        let header: String?
        let footer: String?
        let rows: [Row]
    }

    private lazy var tableView: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()

    private var sections: [Section] {
        var sponsorBlockRows: [Row] = [.sponsorBlockEnabled]
        if SponsorBlockService.enabled { sponsorBlockRows.append(.sponsorBlockSettings) }
        let rydFooter = "Dislike counts are powered by Return YouTube Dislike"
            + " (returnyoutubedislike.com) — an open community project."
        let sbFooter = SponsorBlockService.enabled
            ? SponsorBlockService.attributionText
            : nil
        return [
            Section(header: "Theme", footer: nil, rows: [.theme]),
            Section(header: "Playback", footer: nil, rows: [.quality, .backgroundPlayback]),
            Section(header: "Cache", footer: nil, rows: [.persistCache, .clearCache]),
            Section(header: "Return YouTube Dislike", footer: rydFooter, rows: [.rydEnabled]),
            Section(header: "SponsorBlock", footer: sbFooter, rows: sponsorBlockRows)
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismiss(_:))
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate   = self
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
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor  = theme.separator
        tableView.reloadData()
    }

    @objc
    private func dismiss(_ sender: Any) { dismiss(animated: true) }
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
            let bgOn = BackgroundPlaybackService.isEnabled
            return makeToggleCell("Background Playback", isOn: bgOn) {
                BackgroundPlaybackService.isEnabled = $0
                BackgroundPlaybackService.apply()
            }
        case .persistCache:
            return makeToggleCell("Keep feed cache 24h", isOn: AppCache.persistenceEnabled) {
                AppCache.persistenceEnabled = $0
            }
        case .clearCache:
            return makeDestructiveCell("Clear All Cache")
        case .rydEnabled:
            let rydOn = ReturnYouTubeDislikeService.enabled
            return makeToggleCell("Return YouTube Dislike", isOn: rydOn) {
                ReturnYouTubeDislikeService.enabled = $0
            }
        case .sponsorBlockEnabled:
            return makeSponsorBlockToggle()
        case .sponsorBlockSettings:
            return makeDisclosureCell("SponsorBlock Settings")
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .quality:
            showQualityPicker()
        case .clearCache:
            clearCache()
        case .sponsorBlockSettings:
            showSponsorBlockSettings()
        default:
            break
        }
    }

    private func makeToggleCell(
        _ title: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> UITableViewCell {
        let cell = ToggleCell()
        cell.configure(title: title, isOn: isOn)
        cell.onToggle = onChange
        return cell
    }
    private func makeDisclosureCell(_ title: String, value: String? = nil) -> UITableViewCell {
        let theme = ThemeManager.shared
        let cell = UITableViewCell(style: value != nil ? .value1 : .default, reuseIdentifier: nil)
        cell.textLabel?.text            = title
        cell.textLabel?.textColor       = theme.primaryText
        cell.detailTextLabel?.text      = value
        cell.detailTextLabel?.textColor = theme.secondaryText
        cell.backgroundColor            = theme.surface
        cell.accessoryType              = .disclosureIndicator
        return cell
    }
    private func makeDestructiveCell(_ title: String) -> UITableViewCell {
        let theme = ThemeManager.shared
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text      = title
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.backgroundColor      = theme.surface
        return cell
    }
    private func makeThemeCell() -> UITableViewCell {
        let theme = ThemeManager.shared
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text      = "Theme"
        cell.textLabel?.textColor = theme.primaryText
        cell.backgroundColor      = theme.surface
        cell.selectionStyle       = .none
        let seg = UISegmentedControl(items: ["Dark", "Light", "Auto"])
        let modeMap: [ThemeMode: Int] = [.dark: 0, .light: 1, .auto: 2]
        seg.selectedSegmentIndex = modeMap[theme.themeMode, default: 2]
        seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
        cell.accessoryView = seg
        return cell
    }
    private func makeSponsorBlockToggle() -> UITableViewCell {
        makeToggleCell("SponsorBlock", isOn: SponsorBlockService.enabled) { [weak self] isOn in
            SponsorBlockService.enabled = isOn
            self?.reloadSponsorBlockSection()
        }
    }

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

    @objc
    private func themeChanged(_ seg: UISegmentedControl) {
        let modes: [ThemeMode] = [.dark, .light, .auto]
        let idx = seg.selectedSegmentIndex
        ThemeManager.shared.themeMode = idx >= 0 && idx < modes.count ? modes[idx] : .auto
    }

    private func showQualityPicker() {
        let sheet = UIAlertController(
            title: "Default Quality",
            message: nil,
            preferredStyle: .actionSheet
        )
        VideoQualityStore.options.forEach { opt in
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
        let alert = UIAlertController(
            title: "Cache Cleared",
            message: "Image and feed cache has been cleared.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - ToggleCell

private final class ToggleCell: UITableViewCell {
    var onToggle: ((Bool) -> Void)?
    private let toggle = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        toggle.addTarget(self, action: #selector(handleToggle), for: .valueChanged)
        accessoryView = toggle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isOn: Bool) {
        let theme = ThemeManager.shared
        textLabel?.text      = title
        textLabel?.textColor = theme.primaryText
        backgroundColor      = theme.surface
        toggle.isOn          = isOn
    }

    @objc
    private func handleToggle() { onToggle?(toggle.isOn) }
}

// MARK: - VideoQualityStore

enum VideoQualityStore {
    static let options = ["Auto", "1080p", "720p", "480p", "360p"]
    static var selected: String {
        get {
            let key = UserDefaultsKeys.VideoQuality.selected
            return UserDefaults.standard.string(forKey: key) ?? "Auto"
        }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.VideoQuality.selected) }
    }
    static var displayName: String { selected }

    /// Returns the maximum height for the selected quality.
    static var maxHeight: Int? {
        ["1080p": 1_080, "720p": 720, "480p": 480, "360p": 360][selected]
    }
}
