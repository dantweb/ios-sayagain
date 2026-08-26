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
            makeTranscriber: { requested in
                Self.makeStreamingTranscriber(config: config, requestedLanguages: requested)
            }
        )
    }

    /// Builds the streaming transcriber for a session's recognition-language selection.
    ///
    /// Routing (config-driven, `engines.recognition`):
    /// - If any requested language is NOT in the Apple-native set, hand off to
    ///   `WhisperStreamingTranscriber` — it can transcribe every whisper-supported locale
    ///   and auto-detects when multiple are requested.
    /// - Otherwise, use `AppleSpeechTranscriber` — better UX (volatile updates, on-device
    ///   streaming, lower latency).
    nonisolated static func makeStreamingTranscriber(
        config: SayAgainConfiguration,
        requestedLanguages: [String]
    ) -> any StreamingTranscriber {
        let nativeSet: Set<String> = Set(
            config.engines?.recognition.native ?? config.transcription.spokenLanguages
        )
        let allNative = requestedLanguages.allSatisfy { nativeSet.contains($0) }

        if allNative {
            return AppleSpeechTranscriber(clock: SystemClock())
        }
        return WhisperStreamingTranscriber(
            engine: WhisperTranscriptionEngine(),
            endpointerConfig: config.endpointer,
            clock: SystemClock()
        )
    }
}
