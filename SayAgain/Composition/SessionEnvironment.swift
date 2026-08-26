import Foundation

@MainActor
enum SessionEnvironment {
    static func makeViewModel() -> SessionViewModel {
        let config: SayAgainConfiguration
        do {
            config = try SayAgainConfiguration.loadFromBundle()
        } catch {
            fatalError("SayAgain: config.json missing or malformed — \(error)")
        }

        let catalog = AppleLanguageCatalog(
            allowedSources: config.transcription.spokenLanguages,
            allowedTargets: config.translation.availableTargets
        )

        let bridge = TranslationBridge()
        let translator = BridgeTranslator(bridge: bridge)
        let preferences = LanguagePreferences()

        return SessionViewModel(
            config: config,
            catalog: catalog,
            translationBridge: bridge,
            preferences: preferences,
            translator: translator,
            makeTranscriber: { AppleSpeechTranscriber(clock: SystemClock()) }
        )
    }
}
