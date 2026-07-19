import Foundation

/// UI languages the app ships `.lproj` bundles for. Adding a language =
/// adding its case + a translated `Localizable.strings`
/// (see docs/plans/localization.md, Phase 4). RTL languages are deferred
/// until a leading/trailing constraint audit.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"
    case afrikaans = "af"
    case amharic = "am"
    case azerbaijani = "az"
    case belarusian = "be"
    case bulgarian = "bg"
    case bengali = "bn"
    case bosnian = "bs"
    case catalan = "ca"
    case czech = "cs"
    case danish = "da"
    case german = "de"
    case greek = "el"
    case spanish = "es"
    case estonian = "et"
    case basque = "eu"
    case finnish = "fi"

    /// The user's in-app override, nil = follow the system language.
    static var override: AppLanguage? {
        get {
            let stored = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Localization.appLanguage
            )
            return stored.flatMap(AppLanguage.init(rawValue:))
        }
        set {
            UserDefaults.standard.set(
                newValue?.rawValue,
                forKey: UserDefaultsKeys.Localization.appLanguage
            )
            LocalizationManager.shared.reload()
        }
    }

    /// The effective UI language: the override, else the closest supported
    /// match to the system language, else English.
    static var effective: AppLanguage {
        if let override {
            return override
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if let lang = AppLanguage(rawValue: preferred) {
            return lang
        }
        let parts = preferred.split(separator: "-")
        if parts.count >= 2 {
            let withoutRegion = parts.prefix(2).joined(separator: "-")
            if let lang = AppLanguage(rawValue: withoutRegion) {
                return lang
            }
        }
        let langCode = String(preferred.prefix(2))
        return AppLanguage(rawValue: langCode) ?? .english
    }

    /// Native-script name for the settings picker.
    var displayName: String {
        switch self {
        case .english:
            "English"
        case .russian:
            "Русский"
        case .afrikaans:
            "Afrikaans"
        case .amharic:
            "አማርኛ"
        case .azerbaijani:
            "Azərbaycanca"
        case .belarusian:
            "Беларуская"
        case .bulgarian:
            "Български"
        case .bengali:
            "বাংলা"
        case .bosnian:
            "Bosanski"
        case .catalan:
            "Català"
        case .czech:
            "Čeština"
        case .danish:
            "Dansk"
        case .german:
            "Deutsch"
        case .greek:
            "Ελληνικά"
        case .spanish:
            "Español"
        case .estonian:
            "Eesti"
        case .basque:
            "Euskara"
        case .finnish:
            "Suomi"
        }
    }
}
