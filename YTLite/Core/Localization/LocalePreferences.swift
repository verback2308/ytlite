import Foundation

/// Content language (`hl`) and region (`gl`) for Innertube requests.
/// Injected into `Core/API` via `ServiceContainer`/`AppDependencies`;
/// Phase 2 of the localization plan points `InnertubeContexts` here
/// instead of its hardcoded `"en"`/`"US"` literals. Features never read
/// this directly.
protocol LocalePreferences {
    var hl: String { get }
    var gl: String { get }
}

/// UserDefaults-backed preferences: content FOLLOWS THE APP LANGUAGE —
/// the official client behaves the same way, and a separate content
/// language proved to be a useless extra knob (it also allowed picking a
/// language without a ContentKeywords table, silently degrading metadata
/// parsing). Region stays independent.
struct DefaultLocalePreferences: LocalePreferences {
    var hl: String { AppLanguage.effective.rawValue }

    var gl: String {
        UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Localization.region
        ) ?? Locale.current.regionCode ?? "US"
    }
}
