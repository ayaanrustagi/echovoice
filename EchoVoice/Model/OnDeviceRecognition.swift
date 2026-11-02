import Foundation
import Speech

/// Tries regional variants of the app language without ever using a server.
enum OnDeviceRecognition {
    static func recognizer() -> SFSpeechRecognizer? {
        let preferred = AppLanguage.speechLocale
        let fallback = Locale(identifier: AppLanguage.isSpanish ? "es-MX" : "en-US")
        let supported = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == AppLanguage.code }
            .sorted { $0.identifier < $1.identifier }
        for locale in [preferred, fallback] + supported {
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }
}
