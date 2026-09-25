import Foundation
#if SAYAGAINPLUS_TIER
import Speech
#endif

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
        // Each SKU loads its own config file so language lists and the presence of the
        // `engines` block match what the tier can actually deliver.
        #if SAYAGAINPLUS_TIER
        let configName = "config-plus"
        #else
        let configName = "config"
        #endif

        let config: SayAgainConfiguration
        do {
            config = try SayAgainConfiguration.loadFromBundle(name: configName)
        } catch {
            fatalError("SayAgain: \(configName).json missing or malformed — \(error)")
        }

        let catalog = AppleLanguageCatalog(
            allowedSources: config.transcription.spokenLanguages,
            allowedTargets: config.translation.availableTargets
        )

        let bridge = TranslationBridge()
        let preferences = LanguagePreferences()

        #if SAYAGAINPLUS_TIER
        let bridgeTranslator = BridgeTranslator(bridge: bridge)
        let llm = MLXLLMTranslator()
        let llmLanguages: Set<String> = Set(config.engines?.translation.llm ?? [])
        let translator: any Translating = CompoundTranslator(
            native: bridgeTranslator,
            llm: llm,
            llmLanguages: llmLanguages
        )
        let makeTranscriber: @Sendable ([String]) -> any StreamingTranscriber = { requested in
            makeStreamingTranscriberPlus(config: config, requestedLanguages: requested)
        }
        let downloadManager = ModelDownloadManager()
        return SessionViewModel(
            config: config,
            catalog: catalog,
            translationBridge: bridge,
            preferences: preferences,
            translator: translator,
            makeTranscriber: makeTranscriber,
            downloadManager: downloadManager
        )
        #else
        let translator: any Translating = BridgeTranslator(bridge: bridge)
        let makeTranscriber: @Sendable ([String]) -> any StreamingTranscriber = { _ in
            AppleSpeechTranscriber(clock: SystemClock())
        }
        return SessionViewModel(
            config: config,
            catalog: catalog,
            translationBridge: bridge,
            preferences: preferences,
            translator: translator,
            makeTranscriber: makeTranscriber
        )
        #endif
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
        // `SpeechTranscriber.isAvailable` is false on devices without Apple Intelligence
        // (iPhone 14 and earlier, most iPads without M-series chips) and inside the
        // Simulator. When that's the case, skip Apple STT and go straight to Whisper —
        // otherwise the user picks a supported language, the framework has no assets,
        // and nothing transcribes.
        let appleAvailable = SpeechTranscriber.isAvailable
        let useApple = allNative && appleAvailable
        print("SessionEnvironment[Plus]: requested=\(requestedLanguages) allNative=\(allNative) appleAvailable=\(appleAvailable) → \(useApple ? "AppleSpeechTranscriber" : "WhisperStreamingTranscriber")")
        if useApple {
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
