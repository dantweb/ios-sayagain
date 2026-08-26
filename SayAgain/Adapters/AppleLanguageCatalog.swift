import Foundation
import Translation

nonisolated final class AppleLanguageCatalog: LanguageCatalog, @unchecked Sendable {
    private let allowedSources: [String]
    private let allowedTargets: [String]

    init(allowedSources: [String], allowedTargets: [String]) {
        self.allowedSources = allowedSources
        self.allowedTargets = allowedTargets
    }

    /// Returns every configured target unfiltered. The SwiftUI `TranslationBridge` handles
    /// the actual availability check at translate-time — including prompting the user to
    /// download a missing language pack. This keeps the dropdown honest about the app's
    /// *intent* while letting the system arbitrate feasibility per pair.
    func availableTargets() async -> [TranslationLanguage] {
        allowedTargets.map { code in
            let displayName = Locale.current.localizedString(forLanguageCode: code) ?? code
            return TranslationLanguage(code: code, displayName: displayName)
        }
    }
}
