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
        let bridgeTranslator = BridgeTranslator(bridge: bridge)
        let nllb = NLLBTranslator()

        // CompoundTranslator picks the right backend per pair, driven by config.
        let nllbTargets: Set<String> = Set(config.engines?.translation.nllb ?? [])
        let compound = CompoundTranslator(
            native: bridgeTranslator,
            nllb: nllb,
            nllbTargets: nllbTargets
        )

        let preferences = LanguagePreferences()

        return SessionViewModel(
            config: config,
            catalog: catalog,
            translationBridge: bridge,
            preferences: preferences,
            translator: compound,
            makeTranscriber: { Self.makeStreamingTranscriber(config: config) }
        )
    }

    /// Constructs the streaming transcriber the session uses. For now this is always the
    /// Apple native transcriber; slice 2 will introduce a composite that routes per-locale
    /// (Apple for supported locales, `EndpointedTranscriber(engine: WhisperTranscriptionEngine())`
    /// for the rest).
    nonisolated static func makeStreamingTranscriber(config: SayAgainConfiguration) -> any StreamingTranscriber {
        AppleSpeechTranscriber(clock: SystemClock())
    }
}
