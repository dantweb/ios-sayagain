import Foundation
import Observation
import UIKit

struct DisplayedLine: Identifiable, Sendable, Hashable {
    let line: TranscriptLine
    var translations: [String: String]
    var id: UUID { line.id }
}

@Observable
@MainActor
final class SessionViewModel {

    // Observed state — bound to the UI (Observation framework, no Combine).
    var finalisedLines: [DisplayedLine] = []
    var volatileText: String = ""
    /// The full set of configured languages — used by onboarding and Settings.
    var configuredLanguages: [TranslationLanguage] = []
    var selectedTarget: TranslationLanguage? = nil
    var isRunning: Bool = false
    var micPermission: MicrophonePermissionStatus = .notDetermined
    var errorMessage: String? = nil
    /// True while a session is loading the STT/MT models into memory. Displayed as a
    /// "Warming up engines…" banner so users understand why the first few seconds of
    /// silence exists on Plus tier (Whisper-small ~15-30s cold-load, Qwen ~30-60s).
    /// Clears once both warmups return.
    var isWarmingUp: Bool = false

    /// Languages shown in the "Translate to" dropdown — configured intersected with the user's picks.
    var availableTargets: [TranslationLanguage] {
        let picked = preferences.selectedTargets
        if picked.isEmpty { return configuredLanguages }
        return configuredLanguages.filter { picked.contains($0.code) }
    }

    /// Languages the transcriber may listen for (recognition). Comes from config.json.
    var recognitionLanguages: [String] {
        config.transcription.spokenLanguages
    }

    /// Languages we plan to add in a future release — shown in Settings as disabled
    /// with a "coming in the next version" note so users know the gap is intentional.
    var plannedRecognitionLanguages: [String] {
        config.planned?.recognition ?? []
    }

    var plannedTranslationLanguages: [String] {
        config.planned?.translation ?? []
    }

    #if SAYAGAINPLUS_TIER
    /// Targets that route through the on-device LLM instead of Apple Translation.
    /// SettingsView uses this to keep RO/HU/TH selectable when the LLM pack is installed,
    /// even though `LanguageAvailabilityService` (which only knows Apple) reports them as
    /// unsupported.
    var llmTranslationLanguages: Set<String> {
        Set(config.engines?.translation.llm ?? [])
    }
    #endif

    // Injected dependencies.
    let translationBridge: TranslationBridge   // exposed so the view can attach .translationTask
    let preferences: LanguagePreferences       // exposed so views can bind to onboarding / settings
    #if SAYAGAINPLUS_TIER
    /// Exposed to Settings so the Language Packs section can drive downloads.
    let downloadManager: ModelDownloadManager
    #endif
    private let config: SayAgainConfiguration
    private let catalog: any LanguageCatalog
    private let translator: any Translating
    /// Factory takes the sorted list of user-picked recognition candidates so the Plus
    /// tier can route between Apple STT and Whisper. The base tier ignores the argument.
    private let makeTranscriber: @Sendable ([String]) -> any StreamingTranscriber

    // Per-session state.
    private var transcriptionCoordinator: TranscriptionCoordinator?
    private var translationCoordinator: TranslationCoordinator?
    private var displayTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    #if SAYAGAINPLUS_TIER
    init(
        config: SayAgainConfiguration,
        catalog: any LanguageCatalog,
        translationBridge: TranslationBridge,
        preferences: LanguagePreferences,
        translator: any Translating,
        makeTranscriber: @Sendable @escaping ([String]) -> any StreamingTranscriber,
        downloadManager: ModelDownloadManager
    ) {
        self.config = config
        self.catalog = catalog
        self.translationBridge = translationBridge
        self.preferences = preferences
        self.translator = translator
        self.makeTranscriber = makeTranscriber
        self.downloadManager = downloadManager
    }
    #else
    init(
        config: SayAgainConfiguration,
        catalog: any LanguageCatalog,
        translationBridge: TranslationBridge,
        preferences: LanguagePreferences,
        translator: any Translating,
        makeTranscriber: @Sendable @escaping ([String]) -> any StreamingTranscriber
    ) {
        self.config = config
        self.catalog = catalog
        self.translationBridge = translationBridge
        self.preferences = preferences
        self.translator = translator
        self.makeTranscriber = makeTranscriber
    }
    #endif

    // MARK: - Lifecycle

    func onAppear() async {
        micPermission = MicrophonePermission.status()
        configuredLanguages = await catalog.availableTargets()
    }

    func start() async {
        errorMessage = nil

        if micPermission != .granted {
            micPermission = await MicrophonePermission.request()
            if micPermission != .granted {
                errorMessage = "Enable Microphone access in Settings to use SayAgain."
                return
            }
        }

        finalisedLines.removeAll()
        volatileText = ""

        let docs = documentsDirectory()
        let mainURL = docs.appendingPathComponent(config.transcript.mainFilename)

        do {
            let mainSink = try FileTranscriptSink(
                url: mainURL,
                config: SinkConfig(
                    truncateOnOpen: config.transcript.truncateOnSessionStart,
                    timestampFormat: config.transcript.timestampFormat
                )
            )

            let candidates = Array(preferences.recognitionLanguages).sorted()
            let transcriber = makeTranscriber(candidates)
            let policy = TranscriptionPolicy(config: config.transcription)
            let transcription = TranscriptionCoordinator(
                transcriber: transcriber,
                sink: mainSink,
                policy: policy,
                clock: SystemClock()
            )
            self.transcriptionCoordinator = transcription

            let prefix = config.translation.outputFilePrefix
            let ext = config.translation.outputFileExtension
            let timestampFormat = config.transcript.timestampFormat
            // Optional-returning so a mid-session target switch that hits a filesystem
            // error (permissions, disk full, whatever) can't crash the app via `try!`.
            // TranslationCoordinator drops writes for nil sinks; translations still emit
            // events, just don't persist to a per-target file.
            let sinkFactory: @Sendable (String) -> (any TranscriptSink)? = { target in
                let url = docs.appendingPathComponent("\(prefix).\(target).\(ext)")
                do {
                    return try FileTranscriptSink(
                        url: url,
                        config: SinkConfig(truncateOnOpen: true, timestampFormat: timestampFormat)
                    )
                } catch {
                    print("SessionViewModel: could not open sink for '\(target)': \(error)")
                    return nil
                }
            }

            let translation = TranslationCoordinator(
                translator: translator,
                sinkFactory: sinkFactory,
                cacheLimit: config.translation.cacheLimit,
                clock: SystemClock()
            )
            self.translationCoordinator = translation

            if let target = selectedTarget {
                await translation.setTargets([target.code])
            }

            let displayStream = transcription.stream
            displayTask = Task { [weak self] in
                for await event in displayStream {
                    await self?.handle(display: event)
                }
            }

            let translationStream = translation.stream
            translationTask = Task { [weak self] in
                for await event in translationStream {
                    await self?.handle(translation: event)
                }
            }

            // Warm up engines SERIALLY, Whisper first. Running them in parallel caused
            // Metal command-queue contention: MLX's ~1 GB Qwen load competes with
            // WhisperKit's live utterance decode on the same GPU, producing random
            // multi-second stalls in the transcript stream. Whisper's model loads in
            // ~15-30s; after that its per-utterance decode is ANE-heavy and light on
            // GPU, so LLM loading can start without stealing Whisper's cycles.
            //
            // `isWarmingUp` stays true across both loads so the banner only clears when
            // the whole pipeline is hot.
            let transcriberRef = transcriber
            let translatorRef = translator
            isWarmingUp = true
            Task { [weak self] in
                await transcriberRef.warmUp()
                await translatorRef.warmUp()
                // Task inherits @MainActor isolation from `start()`, so by the time
                // both awaits return we're back on the main actor.
                self?.isWarmingUp = false
            }

            // Recognition candidates come from the user's Default-language selection in Settings.
            try await transcription.start(spokenLanguages: candidates)
            isRunning = true
            // Keep the phone awake while a session runs. Screen may still dim/lock, but
            // background transcription continues.
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            await tearDown()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func stop() async {
        await transcriptionCoordinator?.stop()
        await translationCoordinator?.close()
        await tearDown()
        volatileText = ""
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func cancel() async {
        await transcriptionCoordinator?.cancel()
        try? await translationCoordinator?.discardAll()
        await tearDown()
        finalisedLines.removeAll()
        volatileText = ""
        isRunning = false
        sweepSessionFiles()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func clean() async {
        await cancel()
        sweepSessionFiles()   // idempotent — catches leftovers from prior sessions
    }

    /// Mid-session target-language switch. Safe to call while transcription is running:
    /// the translation coordinator swaps sinks atomically and any in-flight translation
    /// for the previous target simply lands in a now-nil dict entry (writes drop, events
    /// still stream). Wrapped in a try/catch so any filesystem or actor failure surfaces
    /// to `errorMessage` rather than crashing the session.
    func setTarget(_ target: TranslationLanguage?) async {
        let previous = selectedTarget?.code
        selectedTarget = target
        print("SessionViewModel: setTarget \(previous ?? "nil") → \(target?.code ?? "nil")")
        guard let coord = translationCoordinator else { return }
        do {
            if let code = target?.code {
                try await Task { await coord.setTargets([code]) }.value
            } else {
                try await Task { await coord.setTargets([]) }.value
            }
        } catch {
            errorMessage = "Failed to switch translation target: \(error.localizedDescription)"
            print("SessionViewModel: setTarget failed — \(error)")
        }
    }

    // MARK: - Export

    var currentSnapshot: SessionSnapshot {
        let start = finalisedLines.first?.line.time ?? Date()
        let lines = finalisedLines.map { FinalisedLine(line: $0.line, translations: $0.translations) }
        return SessionSnapshot(lines: lines, startedAt: start)
    }

    // MARK: - Internals

    private func tearDown() async {
        displayTask?.cancel(); displayTask = nil
        translationTask?.cancel(); translationTask = nil
        transcriptionCoordinator = nil
        translationCoordinator = nil
    }

    private func handle(display event: DisplayEvent) async {
        switch event {
        case .volatileUpdated(let text):
            volatileText = text
        case .finalised(let line):
            print("SessionViewModel: .finalised → appending '\(line.text)' (now \(finalisedLines.count + 1) lines)")
            volatileText = ""
            finalisedLines.append(DisplayedLine(line: line, translations: [:]))
            if let coord = translationCoordinator {
                // Fire-and-forget: don't block the display stream on translation, which can
                // take 10-30s per call for the on-device LLM. Serialisation is handled by
                // TranslationCoordinator's actor; ordering is preserved by the enqueue order.
                Task { await coord.handleFinal(line) }
            }
        case .failure(let failure):
            errorMessage = String(describing: failure)
        }
    }

    private func handle(translation event: TranslationEvent) async {
        switch event {
        case .translated(let source, let target, let text):
            attachTranslation(sourceId: source.id, target: target, text: text)
        case .skipped(let source, let target, .sameLanguage):
            attachTranslation(sourceId: source.id, target: target, text: source.text)
        case .skipped:
            break
        case .failed(let source, let target, let failure):
            let message: String
            switch failure {
            case .backendFailed(let reason): message = "⚠︎ \(reason)"
            case .noRoute:                   message = "⚠︎ no route to \(target)"
            case .cancelled:                 message = "⚠︎ cancelled"
            }
            print("SayAgain translation failure for '\(source.text)' → \(target): \(message)")
            attachTranslation(sourceId: source.id, target: target, text: message)
        }
    }

    private func attachTranslation(sourceId: UUID, target: String, text: String) {
        guard let idx = finalisedLines.firstIndex(where: { $0.line.id == sourceId }) else { return }
        var updated = finalisedLines[idx]
        updated.translations[target] = text
        finalisedLines[idx] = updated
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func sweepSessionFiles() {
        let docs = documentsDirectory()
        let mainURL = docs.appendingPathComponent(config.transcript.mainFilename)
        try? FileManager.default.removeItem(at: mainURL)
        if let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            let prefix = config.translation.outputFilePrefix + "."
            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
