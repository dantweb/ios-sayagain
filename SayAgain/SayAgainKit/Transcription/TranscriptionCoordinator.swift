import Foundation

actor TranscriptionCoordinator {
    private let transcriber: any StreamingTranscriber
    private let sink: any TranscriptSink
    private let policy: TranscriptionPolicy
    private let clock: any ClockProviding
    private let filter: HallucinationFilter

    private let continuation: AsyncStream<DisplayEvent>.Continuation
    nonisolated let stream: AsyncStream<DisplayEvent>

    private var task: Task<Void, Never>?
    private var currentVolatile: String = ""
    private var currentLanguage: String
    private var isRunning: Bool = false

    init(
        transcriber: any StreamingTranscriber,
        sink: any TranscriptSink,
        policy: TranscriptionPolicy,
        clock: any ClockProviding
    ) {
        self.transcriber = transcriber
        self.sink = sink
        self.policy = policy
        self.clock = clock
        self.filter = HallucinationFilter(blocklist: policy.hallucinationBlocklist)
        self.currentLanguage = policy.allowedLanguages.first ?? "en"

        var cont: AsyncStream<DisplayEvent>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start(spokenLanguages: [String]) async throws {
        guard !isRunning else { return }
        isRunning = true
        try await transcriber.start(spokenLanguages: spokenLanguages)

        let events = transcriber.events
        task = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    func stop() async {
        guard isRunning else { return }
        // Test 3.14 — finalise volatile mid-phrase; last words survive.
        if !currentVolatile.isEmpty {
            await finalise(text: currentVolatile, at: clock.now(), language: currentLanguage, confidence: nil)
            currentVolatile = ""
        }
        await transcriber.stop()
        task?.cancel()
        task = nil
        isRunning = false
        await sink.close()
        continuation.finish()
    }

    func cancel() async {
        guard isRunning else { return }
        currentVolatile = ""
        await transcriber.stop()
        task?.cancel()
        task = nil
        isRunning = false
        try? await sink.discard()
        continuation.finish()
    }

    // MARK: - Internal

    private func handle(_ event: TranscriptionEvent) async {
        switch event {
        case .volatile(let text):
            // Test 3.12 — volatile is NEVER written to sink; only display.
            currentVolatile = text
            continuation.yield(.volatileUpdated(text))

        case .final(let line):
            // Language pinning: if only one allowed, override detection.
            let resolvedLanguage: String
            if policy.allowedLanguages.count == 1, let only = policy.allowedLanguages.first {
                resolvedLanguage = only
            } else if policy.allowedLanguages.contains(line.language) {
                resolvedLanguage = line.language
            } else {
                // Detection outside the allowed set: keep original (degrade, don't crash).
                resolvedLanguage = line.language
            }
            currentLanguage = resolvedLanguage
            currentVolatile = ""
            await finalise(text: line.text, at: line.time, language: resolvedLanguage, confidence: line.confidence, existingID: line.id)

        case .failed(let failure):
            // Test 3.10 — one bad utterance ≠ a lost session.
            continuation.yield(.failure(failure))
        }
    }

    private func finalise(text: String, at time: Date, language: String, confidence: Double?, existingID: UUID? = nil) async {
        let filtered = filter.strip(text)
        // Test 3.9 — a line that is entirely hallucination yields no line.
        guard !filtered.isEmpty else { return }
        let line = TranscriptLine(
            id: existingID ?? UUID(),
            time: time,
            language: language,
            text: filtered,
            confidence: confidence
        )
        try? await sink.write(line)
        continuation.yield(.finalised(line))
    }
}
