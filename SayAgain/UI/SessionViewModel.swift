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

    // Injected dependencies.
    let translationBridge: TranslationBridge   // exposed so the view can attach .translationTask
    let preferences: LanguagePreferences       // exposed so views can bind to onboarding / settings
    private let config: SayAgainConfiguration
    private let catalog: any LanguageCatalog
    private let translator: any Translating
    private let makeTranscriber: @Sendable () -> AppleSpeechTranscriber

    // Per-session state.
    private var transcriptionCoordinator: TranscriptionCoordinator?
    private var translationCoordinator: TranslationCoordinator?
    private var displayTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    init(
        config: SayAgainConfiguration,
        catalog: any LanguageCatalog,
        translationBridge: TranslationBridge,
        preferences: LanguagePreferences,
        translator: any Translating,
        makeTranscriber: @Sendable @escaping () -> AppleSpeechTranscriber
    ) {
        self.config = config
        self.catalog = catalog
        self.translationBridge = translationBridge
        self.preferences = preferences
        self.translator = translator
        self.makeTranscriber = makeTranscriber
    }

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

            let transcriber = makeTranscriber()
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
            let sinkFactory: @Sendable (String) -> any TranscriptSink = { target in
                let url = docs.appendingPathComponent("\(prefix).\(target).\(ext)")
                return try! FileTranscriptSink(
                    url: url,
                    config: SinkConfig(truncateOnOpen: true, timestampFormat: timestampFormat)
                )
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

            // Recognition candidates come from the user's Default-language selection in Settings.
            // One language = fast + accurate. Multiple = multi-language guessing at higher cost.
            let candidates = Array(preferences.recognitionLanguages).sorted()
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

    func setTarget(_ target: TranslationLanguage?) async {
        selectedTarget = target
        guard let coord = translationCoordinator else { return }
        if let code = target?.code {
            await coord.setTargets([code])
        } else {
            await coord.setTargets([])
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
            volatileText = ""
            finalisedLines.append(DisplayedLine(line: line, translations: [:]))
            if let coord = translationCoordinator {
                await coord.handleFinal(line)
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
