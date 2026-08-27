import Foundation

/// Composition root for the SessionViewModel. Two variants live behind a compile flag:
///
/// - **SayAgain** (no `SAYAGAINPLUS_TIER` flag): Apple-native only. STT via
///   `AppleSpeechTranscriber`, MT via `BridgeTranslator`. Locales Apple doesn't cover
///   are surfaced in Settings under "Planned languages" but not selectable.
/// - **SayAgainPlus** (`SAYAGAINPLUS_TIER` set in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`):
///   adds WhisperKit STT for the Apple-uncovered locales and routes non-native
///   translation pairs through `NLLBTranslator` (once its model ships).
///
/// Both variants build from the same `main` branch — the flag decides which composition
/// closes over the shared `SessionViewModel` construction site.
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
        let preferences = LanguagePreferences()

        #if SAYAGAINPLUS_TIER
        let bridgeTranslator = BridgeTranslator(bridge: bridge)
        let nllb = NLLBTranslator()
        let nllbTargets: Set<String> = Set(config.engines?.translation.nllb ?? [])
        let translator: any Translating = CompoundTranslator(
            native: bridgeTranslator,
            nllb: nllb,
            nllbTargets: nllbTargets
        )
        let makeTranscriber: @Sendable ([String]) -> any StreamingTranscriber = { requested in
            makeStreamingTranscriberPlus(config: config, requestedLanguages: requested)
        }
        #else
        let translator: any Translating = BridgeTranslator(bridge: bridge)
        let makeTranscriber: @Sendable ([String]) -> any StreamingTranscriber = { _ in
            AppleSpeechTranscriber(clock: SystemClock())
        }
        #endif

        return SessionViewModel(
            config: config,
            catalog: catalog,
            translationBridge: bridge,
            preferences: preferences,
            translator: translator,
            makeTranscriber: makeTranscriber
        )
    }

    #if SAYAGAINPLUS_TIER
    /// Plus-tier recognition routing. If every requested locale is on the Apple-native
    /// list, use `AppleSpeechTranscriber` for the streaming-UX win. Otherwise hand off
    /// to `WhisperStreamingTranscriber`, which covers ru/pl/ro/hu/th.
    nonisolated static func makeStreamingTranscriberPlus(
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
    #endif
}
