import Foundation

/// Uses the app's resolved language, including iOS per-app and scheme overrides.
enum AppLanguage {
    static var isSpanish: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("es") == true }
    static var code: String { isSpanish ? "es" : "en" }

    static var speechLocale: Locale {
        let current = Locale.current
        if current.language.languageCode?.identifier == code { return current }
        return Locale(identifier: isSpanish ? "es-MX" : "en-US")
    }
}
