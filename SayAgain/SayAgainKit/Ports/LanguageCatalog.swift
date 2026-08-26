import Foundation

nonisolated protocol LanguageCatalog: Sendable {
    func availableTargets() async -> [TranslationLanguage]
}
