import UIKit

// MARK: - Language settings (app language / content language / region)
//
// Three separate concepts (localization plan): UI language, Innertube `hl`
// (titles/search/feeds — YouTube translates metadata server-side), and `gl`
// (region gating). "System" clears the stored override; changes fully apply
// after an app restart, and content/region changes drop the feed cache so
// stale-language pages never resurface.

extension SettingsViewController {
    /// Curated `hl` options — YouTube accepts many more; extend on request.
    private static let contentLanguages = [
        "en", "ru", "uk", "de", "fr", "es", "pt", "it", "pl", "tr",
        "ja", "ko", "hi", "id", "vi", "ar", "th"
    ]
    /// Curated `gl` options.
    private static let regions = [
        "US", "RU", "UA", "DE", "FR", "ES", "PT", "BR", "IT", "PL",
        "TR", "JP", "KR", "IN", "ID", "VN", "SA", "TH", "GB", "CA"
    ]

    /// Names come from iOS's built-in CLDR catalog, rendered in the APP's
    /// UI language (not the device locale) so the list matches the rest of
    /// the interface.
    private var namesLocale: Locale {
        Locale(identifier: AppLanguage.effective.rawValue)
    }

    // MARK: Cells

    func makeAppLanguageCell() -> UITableViewCell {
        makeDisclosureCell(
            "settings.row.appLanguage".localized,
            value: AppLanguage.override?.displayName
                ?? "settings.language.system".localized
        )
    }

    func makeContentLanguageCell() -> UITableViewCell {
        makeDisclosureCell(
            "settings.row.contentLanguage".localized,
            value: storedValueDisplay(
                key: UserDefaultsKeys.Localization.contentLanguage,
                systemValue: InnertubeContexts.localePreferences.hl,
                name: languageName
            )
        )
    }

    func makeRegionCell() -> UITableViewCell {
        makeDisclosureCell(
            "settings.row.region".localized,
            value: storedValueDisplay(
                key: UserDefaultsKeys.Localization.region,
                systemValue: InnertubeContexts.localePreferences.gl,
                name: regionName
            )
        )
    }

    // MARK: Selection

    func handleLanguageSelection(_ row: Row) -> Bool {
        switch row {
        case .appLanguage:
            showAppLanguagePicker()
        case .contentLanguage:
            showContentLanguagePicker()
        case .region:
            showRegionPicker()
        default:
            return false
        }
        return true
    }

    // MARK: - Private

    /// "Name" when overridden, "System (xx)" when following the device.
    private func storedValueDisplay(
        key: String,
        systemValue: String,
        name: (String) -> String
    ) -> String {
        if let stored = UserDefaults.standard.string(forKey: key) {
            return name(stored)
        }
        return "settings.language.system".localized + " (\(systemValue))"
    }

    private func languageName(_ code: String) -> String {
        namesLocale.localizedString(forLanguageCode: code)?
            .capitalized ?? code
    }

    private func regionName(_ code: String) -> String {
        namesLocale.localizedString(forRegionCode: code) ?? code
    }

    private func showAppLanguagePicker() {
        let options = [(nil, "settings.language.system".localized)]
            + AppLanguage.allCases.map { ($0.rawValue, $0.displayName) }
        presentCodePicker(
            title: "settings.row.appLanguage".localized,
            options: options,
            selected: AppLanguage.override?.rawValue
        ) { code in
            AppLanguage.override = code.flatMap(AppLanguage.init(rawValue:))
        }
    }

    private func showContentLanguagePicker() {
        let options = [(nil, "settings.language.system".localized)]
            + Self.contentLanguages.map { ($0 as String?, languageName($0)) }
        presentCodePicker(
            title: "settings.row.contentLanguage".localized,
            options: options,
            selected: UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Localization.contentLanguage
            )
        ) { code in
            UserDefaults.standard.set(
                code, forKey: UserDefaultsKeys.Localization.contentLanguage
            )
            // Cached feed pages carry the old language.
            AppCache.shared.clearAllDiskCache()
        }
    }

    private func showRegionPicker() {
        let options = [(nil, "settings.language.system".localized)]
            + Self.regions.map { ($0 as String?, regionName($0)) }
        presentCodePicker(
            title: "settings.row.region".localized,
            options: options,
            selected: UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Localization.region
            )
        ) { code in
            UserDefaults.standard.set(
                code, forKey: UserDefaultsKeys.Localization.region
            )
            AppCache.shared.clearAllDiskCache()
        }
    }

    /// Shared sheet: "System" + curated codes, checkmark on the current
    /// pick, restart alert after a change.
    private func presentCodePicker(
        title: String,
        options: [(String?, String)],
        selected: String?,
        onPick: @escaping (String?) -> Void
    ) {
        let sheet = UIAlertController(
            title: title, message: nil, preferredStyle: .actionSheet
        )
        for (code, name) in options {
            let action = UIAlertAction(
                title: name, style: .default
            ) { [weak self] _ in
                onPick(code)
                self?.reloadAllSettings()
                self?.presentSimpleAlert(
                    title: "settings.language.restartTitle".localized,
                    message: "settings.language.restartMessage".localized
                )
            }
            if code == selected {
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
}
