// swiftlint:disable file_length
import UIKit

/// Settings popup presented as a sheet from the toolbar.
final class SettingsViewController: UIViewController {
    enum Row {
        case theme, autoDarkStart, autoDarkEnd
        case appLanguage, region
        case quality, backgroundPlayback, pipEnabled, hideStatusBar, showShorts
        case autoZoomToFill
        case autoDubEnabled, autoDubLanguage, autoDubIgnoreAI
        case homeLayout
        case persistCache, feedCacheDays
        case imageCacheEnabled, imageCacheDays
        case clearCache, rydEnabled
        case sponsorBlockEnabled, sponsorBlockSettings
        case playbackSource
        case solverEndpoint
        case shareLog
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
        let rydFooter = "settings.footer.ryd".localized
        let sbFooter = SponsorBlockService.enabled
            ? SponsorBlockService.attributionText
            : nil
        var cacheRows: [Row] = [.persistCache]
        if AppCache.persistenceEnabled {
            cacheRows.append(.feedCacheDays)
        }
        cacheRows.append(.imageCacheEnabled)
        if ThumbnailImageView.cachingEnabled {
            cacheRows.append(.imageCacheDays)
        }
        cacheRows.append(.clearCache)
        var autoDubRows: [Row] = [.autoDubEnabled]
        if AutoDubPreference.isEnabled {
            autoDubRows.append(contentsOf: [.autoDubLanguage, .autoDubIgnoreAI])
        }
        var themeRows: [Row] = [.theme]
        if showsAutoHours {
            themeRows.append(contentsOf: [.autoDarkStart, .autoDarkEnd])
        }
        return [
            Section(
                header: "settings.section.theme".localized,
                footer: themeFooter,
                rows: themeRows
            ),
            Section(
                header: "settings.section.language".localized,
                footer: "settings.footer.language".localized,
                rows: [.appLanguage, .region]
            ),
            Section(
                header: "settings.section.playback".localized,
                footer: "settings.footer.playback".localized,
                rows: [
                    .quality, .backgroundPlayback, .pipEnabled,
                    .hideStatusBar, .autoZoomToFill, .showShorts
                ]
            ),
            Section(
                header: "settings.section.autoDub".localized,
                footer: "settings.footer.autoDub".localized,
                rows: autoDubRows
            ),
            Section(
                header: "settings.section.home".localized,
                footer: "settings.footer.home".localized,
                rows: [.homeLayout]
            ),
            Section(
                header: "settings.section.ryd".localized,
                footer: rydFooter,
                rows: [.rydEnabled]
            ),
            Section(
                header: "settings.section.sponsorblock".localized,
                footer: sbFooter,
                rows: sponsorBlockRows
            ),
            Section(
                header: "settings.section.cache".localized,
                footer: nil,
                rows: cacheRows
            ),
            Section(
                header: "settings.section.debug".localized,
                footer: "settings.footer.debug".localized,
                rows: [.playbackSource, .solverEndpoint, .shareLog]
            ),
            Section(header: nil, footer: appVersionFooter, rows: [])
        ]
    }

    /// iOS 12 auto mode is hour-scheduled; iOS 13+ follows the system.
    private var showsAutoHours: Bool {
        guard ThemeManager.shared.themeMode == .auto else {
            return false
        }
        if #available(iOS 13.0, *) {
            return false
        }
        return true
    }

    private var themeFooter: String? {
        guard ThemeManager.shared.themeMode == .auto else {
            return nil
        }
        if #available(iOS 13.0, *) {
            return "settings.footer.themeAutoSystem".localized
        }
        return "settings.footer.themeAutoHours".localized
    }

    private var appVersionFooter: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "YTLite v\(version) (\(build))"
    }

    private var solverEndpointDisplay: String {
        let custom = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Debug.serverBaseURL
        )
        let isCustom = custom?.isEmpty == false
        return AppURLs.SolverServer.baseURL
            + (isCustom ? "" : "settings.solver.defaultSuffix".localized)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "settings.title".localized
        // Titled, not `barButtonSystemItem: .done` — system items are
        // localized by iOS to the DEVICE language, ignoring the in-app
        // language override.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "common.done".localized,
            style: .done,
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

    /// Full reload for extensions living in other files (tableView is
    /// private to this one).
    func reloadAllSettings() { tableView.reloadData() }

    /// Row-based section reload — headers are localized display text, so
    /// sections are found by their rows, never by title.
    func reloadSection(containing row: Row) {
        if let idx = sections.firstIndex(where: { $0.rows.contains(row) }) {
            tableView.reloadSections(IndexSet(integer: idx), with: .automatic)
        }
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .theme:
            return makeThemeCell()
        case .appLanguage:
            return makeAppLanguageCell()
        case .region:
            return makeRegionCell()
        case .autoDarkStart:
            return makeDisclosureCell(
                "settings.row.darkFrom".localized,
                value: hourLabel(ThemeManager.shared.autoDarkStartHour)
            )
        case .autoDarkEnd:
            return makeDisclosureCell(
                "settings.row.darkUntil".localized,
                value: hourLabel(ThemeManager.shared.autoDarkEndHour)
            )
        case .quality:
            return makeDisclosureCell(
                "settings.row.defaultQuality".localized,
                value: VideoQualityStore.displayName
            )
        case .backgroundPlayback:
            let bgOn = BackgroundPlaybackService.isEnabled
            return makeToggleCell(
                "settings.row.backgroundPlayback".localized, isOn: bgOn
            ) {
                BackgroundPlaybackService.isEnabled = $0
                BackgroundPlaybackService.apply()
            }
        case .pipEnabled:
            let key = UserDefaultsKeys.Player.pipEnabled
            let isOn = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            return makeToggleCell("settings.row.pip".localized, isOn: isOn) {
                UserDefaults.standard.set($0, forKey: key)
            }
        case .hideStatusBar:
            let key = UserDefaultsKeys.Player.hideStatusBarInFullscreen
            let isOn = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            return makeToggleCell(
                "settings.row.hideStatusBar".localized, isOn: isOn
            ) {
                UserDefaults.standard.set($0, forKey: key)
            }
        case .autoZoomToFill:
            let key = UserDefaultsKeys.Player.autoZoomToFill
            let isOn = UserDefaults.standard.bool(forKey: key)
            return makeToggleCell(
                "settings.row.zoomToFill".localized, isOn: isOn
            ) {
                UserDefaults.standard.set($0, forKey: key)
            }
        case .showShorts:
            return makeShowShortsCell()
        case .autoDubEnabled:
            return makeAutoDubToggleCell()
        case .autoDubLanguage:
            return makeAutoDubLanguageCell()
        case .autoDubIgnoreAI:
            return makeAutoDubIgnoreAICell()
        case .homeLayout:
            return makeDisclosureCell(
                "settings.row.homeLayout".localized,
                value: HomeLayout.selected.displayName
            )
        case .persistCache:
            return makeToggleCell(
                "settings.row.feedCache".localized,
                isOn: AppCache.persistenceEnabled
            ) {
                AppCache.persistenceEnabled = $0
                self.reloadCacheSection()
            }
        case .feedCacheDays:
            let days = UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Cache.feedCacheDays
            ) as? Int ?? 1
            return makeDisclosureCell(
                "settings.row.feedCacheDuration".localized,
                value: "settings.daysCount".localized(with: days)
            )
        case .imageCacheEnabled:
            return makeToggleCell(
                "settings.row.imageCache".localized,
                isOn: ThumbnailImageView.cachingEnabled
            ) {
                UserDefaults.standard.set(
                    $0, forKey: UserDefaultsKeys.Cache.imageCacheEnabled
                )
                self.reloadCacheSection()
            }
        case .imageCacheDays:
            let days = UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Cache.imageCacheDays
            ) as? Int ?? 7
            return makeDisclosureCell(
                "settings.row.imageCacheDuration".localized,
                value: "settings.daysCount".localized(with: days)
            )
        case .clearCache:
            return makeDestructiveCell("settings.row.clearCache".localized)
        case .rydEnabled:
            let rydOn = ReturnYouTubeDislikeService.enabled
            return makeToggleCell(
                "settings.row.ryd".localized, isOn: rydOn
            ) {
                ReturnYouTubeDislikeService.enabled = $0
            }
        case .sponsorBlockEnabled:
            return makeSponsorBlockToggle()
        case .sponsorBlockSettings:
            return makeDisclosureCell(
                "settings.row.sponsorblockSettings".localized
            )
        case .shareLog:
            return makeDisclosureCell("settings.row.shareLog".localized)
        case .playbackSource:
            return makeDisclosureCell(
                "settings.row.playbackSource".localized,
                value: PlaybackSource.selected.displayName
            )
        case .solverEndpoint:
            return makeDisclosureCell(
                "settings.row.solverServer".localized,
                value: solverEndpointDisplay
            )
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        let handlers = [
            handleDebugSelection, handleThemeSelection,
            handleLanguageSelection, handleAutoDubSelection,
            handleGeneralSelection
        ]
        _ = handlers.first { $0(row) }
    }

    private func handleGeneralSelection(_ row: Row) -> Bool {
        switch row {
        case .quality:
            showQualityPicker()
        case .feedCacheDays:
            showFeedCacheDaysPicker()
        case .imageCacheDays:
            showImageCacheDaysPicker()
        case .clearCache:
            clearCache()
        case .sponsorBlockSettings:
            showSponsorBlockSettings()
        default:
            return false
        }
        return true
    }

    private func handleDebugSelection(_ row: Row) -> Bool {
        switch row {
        case .shareLog:
            shareDebugLog()
        case .playbackSource:
            showPlaybackSourcePicker()
        case .solverEndpoint:
            showSolverEndpointPicker()
        default:
            return false
        }
        return true
    }

    private func makeShowShortsCell() -> UITableViewCell {
        let isOn = UserDefaults.standard.bool(forKey: UserDefaultsKeys.Feed.showShorts)
        return makeToggleCell(
            "settings.row.showShorts".localized,
            isOn: isOn
        ) {
            UserDefaults.standard.set(
                $0, forKey: UserDefaultsKeys.Feed.showShorts
            )
            NotificationCenter.default.post(
                name: .showShortsSettingDidChange,
                object: nil
            )
        }
    }

    func makeToggleCell(
        _ title: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> UITableViewCell {
        let cell = ToggleCell()
        cell.configure(title: title, isOn: isOn)
        cell.onToggle = onChange
        return cell
    }
    func makeDisclosureCell(_ title: String, value: String? = nil) -> UITableViewCell {
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
        cell.textLabel?.text      = "settings.row.theme".localized
        cell.textLabel?.textColor = theme.primaryText
        cell.backgroundColor      = theme.surface
        cell.selectionStyle       = .none
        let seg = UISegmentedControl(items: [
            "settings.theme.dark".localized,
            "settings.theme.light".localized,
            "settings.theme.auto".localized
        ])
        let modeMap: [ThemeMode: Int] = [.dark: 0, .light: 1, .auto: 2]
        seg.selectedSegmentIndex = modeMap[theme.themeMode, default: 2]
        seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
        cell.accessoryView = seg
        return cell
    }
    private func makeSponsorBlockToggle() -> UITableViewCell {
        makeToggleCell(
            "settings.row.sponsorblock".localized,
            isOn: SponsorBlockService.enabled
        ) { [weak self] isOn in
            SponsorBlockService.enabled = isOn
            self?.reloadSponsorBlockSection()
        }
    }

    private func reloadSponsorBlockSection() {
        reloadSection(containing: .sponsorBlockEnabled)
    }
    private func showSponsorBlockSettings() {
        let vc  = SponsorBlockSettingsViewController()
        let nav = RotatingNavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc
    private func themeChanged(_ seg: UISegmentedControl) {
        let modes: [ThemeMode] = [.dark, .light, .auto]
        let idx = seg.selectedSegmentIndex
        ThemeManager.shared.themeMode = idx >= 0 && idx < modes.count ? modes[idx] : .auto
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func handleThemeSelection(_ row: Row) -> Bool {
        switch row {
        case .autoDarkStart:
            showAutoHourPicker(isStart: true)
        case .autoDarkEnd:
            showAutoHourPicker(isStart: false)
        case .homeLayout:
            showHomeLayoutPicker()
        default:
            return false
        }
        return true
    }

    private func showAutoHourPicker(isStart: Bool) {
        let sheet = UIAlertController(
            title: isStart
                ? "settings.row.darkFrom".localized
                : "settings.row.darkUntil".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        let manager = ThemeManager.shared
        let current = isStart
            ? manager.autoDarkStartHour
            : manager.autoDarkEndHour
        for hour in 0..<24 {
            let action = autoHourAction(hour: hour, isStart: isStart)
            if hour == current {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func autoHourAction(hour: Int, isStart: Bool) -> UIAlertAction {
        UIAlertAction(
            title: hourLabel(hour),
            style: .default
        ) { [weak self] _ in
            if isStart {
                ThemeManager.shared.autoDarkStartHour = hour
            } else {
                ThemeManager.shared.autoDarkEndHour = hour
            }
            self?.tableView.reloadData()
        }
    }

    private func showQualityPicker() {
        let sheet = UIAlertController(
            title: "settings.row.defaultQuality".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        VideoQualityStore.options.forEach { opt in
            let title = opt == "Auto"
                ? "settings.quality.auto".localized : opt
            let action = UIAlertAction(title: title, style: .default) { _ in
                VideoQualityStore.selected = opt
                self.tableView.reloadData()
            }
            if opt == VideoQualityStore.selected {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func showHomeLayoutPicker() {
        let sheet = UIAlertController(
            title: "settings.row.homeLayout".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        for layout in HomeLayout.allCases {
            let action = UIAlertAction(
                title: layout.displayName,
                style: .default
            ) { _ in
                HomeLayout.selected = layout
                self.tableView.reloadData()
            }
            if layout == HomeLayout.selected {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func showFeedCacheDaysPicker() {
        let options = [1, 2, 3, 5, 7]
        let current = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Cache.feedCacheDays
        ) as? Int ?? 1
        let sheet = UIAlertController(
            title: "settings.row.feedCacheDuration".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        for days in options {
            let action = UIAlertAction(
                title: "settings.daysCount".localized(with: days),
                style: .default
            ) { _ in
                UserDefaults.standard.set(
                    days, forKey: UserDefaultsKeys.Cache.feedCacheDays
                )
                self.tableView.reloadData()
            }
            if days == current {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func showPlaybackSourcePicker() {
        let sheet = UIAlertController(
            title: "settings.row.playbackSource".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        let current = PlaybackSource.selected
        for source in PlaybackSource.allCases {
            let action = UIAlertAction(
                title: source.displayName,
                style: .default
            ) { _ in
                UserDefaults.standard.set(
                    source.rawValue,
                    forKey: UserDefaultsKeys.Debug.playbackSource
                )
                self.tableView.reloadData()
            }
            if source == current {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func showSolverEndpointPicker() {
        let alert = UIAlertController(
            title: "settings.row.solverServer".localized,
            message: "settings.solver.message".localized,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = AppURLs.SolverServer.defaultBaseURL
            field.text = AppURLs.SolverServer.baseURL
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(
            UIAlertAction(
                title: "common.save".localized, style: .default
            ) { [weak self, weak alert] _ in
                self?.saveServerBaseURL(alert?.textFields?.first?.text)
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "settings.solver.reset".localized, style: .destructive
            ) { [weak self] _ in
                self?.saveServerBaseURL(nil)
            }
        )
        alert.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        present(alert, animated: true)
    }

    /// Stores a custom base URL, or clears the override (→ default) when the
    /// value is empty / equal to the default.
    private func saveServerBaseURL(_ text: String?) {
        let trimmed = (text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let override = (trimmed.isEmpty || trimmed == AppURLs.SolverServer.defaultBaseURL)
            ? ""
            : trimmed
        UserDefaults.standard.set(
            override,
            forKey: UserDefaultsKeys.Debug.serverBaseURL
        )
        tableView.reloadData()
    }

    private func showImageCacheDaysPicker() {
        let options = [1, 3, 7, 14, 30]
        let current = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Cache.imageCacheDays
        ) as? Int ?? 7
        let sheet = UIAlertController(
            title: "settings.row.imageCacheDuration".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        for days in options {
            let action = UIAlertAction(
                title: "settings.daysCount".localized(with: days),
                style: .default
            ) { _ in
                UserDefaults.standard.set(
                    days, forKey: UserDefaultsKeys.Cache.imageCacheDays
                )
                self.tableView.reloadData()
            }
            if days == current {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func reloadCacheSection() {
        let cacheIndex = sections.firstIndex {
            $0.rows.contains(.persistCache)
        }
        if let cacheIndex {
            tableView.reloadSections(
                IndexSet(integer: cacheIndex),
                with: .none
            )
        }
    }
    private func clearCache() {
        ThumbnailImageView.clearCache()
        AppCache.shared.clearAllDiskCache()
        WatchProgressStore.shared.clearAll()
        presentSimpleAlert(
            title: "settings.cache.clearedTitle".localized,
            message: "settings.cache.clearedMessage".localized
        )
    }

    private func shareDebugLog() {
        guard let data = AppLog.exportLogData(),
              !data.isEmpty
        else {
            presentSimpleAlert(
                title: "settings.log.noneTitle".localized,
                message: "settings.log.noneMessage".localized
            )
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytlite_debug.log")
        try? data.write(to: tempURL)
        let activity = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        configureCenteredPopover(activity)
        present(activity, animated: true)
    }

    func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "common.ok".localized, style: .default)
        )
        present(alert, animated: true)
    }

    func configureCenteredPopover(_ controller: UIViewController) {
        guard let pop = controller.popoverPresentationController
        else { return }
        pop.sourceView = view
        pop.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 0,
            height: 0
        )
        pop.permittedArrowDirections = []
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
    /// 1440p/2160p exist only as av01 — offered solely where decodable.
    static var options: [String] {
        var opts = ["Auto", "1080p", "720p", "480p", "360p"]
        if AV1Support.isHardwareSupported {
            opts.insert(contentsOf: ["2160p", "1440p"], at: 1)
        }
        return opts
    }
    static var selected: String {
        get {
            let key = UserDefaultsKeys.VideoQuality.selected
            return UserDefaults.standard.string(forKey: key) ?? "Auto"
        }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.VideoQuality.selected) }
    }
    /// Display text for the stored value — "Auto" is a stored constant
    /// (never localized in UserDefaults), only its display is translated.
    static var displayName: String {
        selected == "Auto"
            ? "settings.quality.auto".localized : selected
    }

    /// Returns the maximum height for the selected quality. "Auto" caps at
    /// 1080p — the pre-AV1 behavior; higher tiers are explicit opt-in.
    static var maxHeight: Int? {
        [
            "2160p": 2_160, "1440p": 1_440, "1080p": 1_080,
            "720p": 720, "480p": 480, "360p": 360
        ][selected] ?? 1_080
    }
}
