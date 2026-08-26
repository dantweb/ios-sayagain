import Foundation

/// Wraps a batch `TranscriptionEngine` in a streaming face: audio buffers go in, sentences
/// come out via the `events` async stream. Uses the domain `Endpointer` to segment audio on
/// silence, then submits each utterance to the engine.
///
/// Emits `.final` only — batch engines don't provide volatile refinements. If you need
/// volatile behaviour, use a natively-streaming transcriber (e.g. `AppleSpeechTranscriber`).
actor EndpointedTranscriber: StreamingTranscriber {

    private let engine: any TranscriptionEngine
    private let language: String?
    private let clock: any ClockProviding
    private var endpointer: Endpointer

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    nonisolated let events: AsyncStream<TranscriptionEvent>

    private var isRunning = false
    private var pendingUtterances: [Utterance] = []
    private var transcribeTask: Task<Void, Never>?

    init(
        engine: any TranscriptionEngine,
        language: String?,
        endpointerConfig: EndpointerConfig,
        audioSampleRate: Double,
        clock: any ClockProviding
    ) {
        self.engine = engine
        self.language = language
        self.clock = clock
        self.endpointer = Endpointer(
            config: endpointerConfig,
            clock: clock,
            sampleRate: audioSampleRate
        )

        var cont: AsyncStream<TranscriptionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - StreamingTranscriber

    func start(spokenLanguages: [String]) async throws {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false

        // Flush the endpointer — anything still open becomes a final utterance.
        if let tail = endpointer.flush() {
            pendingUtterances.append(tail)
        }

        // Wait for pending transcription to complete before finishing the stream.
        transcribeTask?.cancel()
        transcribeTask = nil

        // Drain any remaining utterances synchronously so the user's last words survive.
        for utterance in pendingUtterances {
            await transcribeAndEmit(utterance)
        }
        pendingUtterances.removeAll()

        continuation.finish()
    }

    // MARK: - Audio input

    /// Feed one raw PCM buffer. The endpointer emits zero or more `Utterance`s, each of which
    /// we transcribe on a detached task so the audio thread doesn't stall.
    func feed(_ buffer: AudioBuffer) {
        guard isRunning else { return }
        let utterances = endpointer.feed(buffer)
        for u in utterances { pendingUtterances.append(u) }
        scheduleDrain()
    }

    private func scheduleDrain() {
        // Coalesce: if a drain task is already running, it will pick up new utterances on
        // the next iteration. If not, start one.
        if transcribeTask != nil { return }
        transcribeTask = Task { [weak self] in
            await self?.drainLoop()
        }
    }

    private func drainLoop() async {
        while true {
            let next: Utterance? = takeNext()
            guard let utterance = next else {
                transcribeTask = nil
                return
            }
            await transcribeAndEmit(utterance)
        }
    }

    private func takeNext() -> Utterance? {
        guard !pendingUtterances.isEmpty else { return nil }
        return pendingUtterances.removeFirst()
    }

    private func transcribeAndEmit(_ utterance: Utterance) async {
        do {
            let result = try await engine.transcribe(utterance.audio, language: language)
            let text = result.segments.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let confidence: Double? = {
                guard !result.segments.isEmpty else { return nil }
                return result.segments.map(\.confidence).reduce(0, +) / Double(result.segments.count)
            }()

            let line = TranscriptLine(
                time: utterance.start,
                language: result.detectedLanguage ?? language ?? "",
                text: text,
                confidence: confidence
            )
            continuation.yield(.final(line))
        } catch {
            continuation.yield(.failed(.engineFailed(String(describing: error))))
        }
    }
}
