import Foundation

actor TranslationCoordinator {
    private let translator: any Translating
    private let sinkFactory: @Sendable (String) -> any TranscriptSink
    private let clock: any ClockProviding

    private var cache: TranslationCache
    private var activeTargets: [String] = []
    private var sinks: [String: any TranscriptSink] = [:]

    private let continuation: AsyncStream<TranslationEvent>.Continuation
    nonisolated let stream: AsyncStream<TranslationEvent>

    init(
        translator: any Translating,
        sinkFactory: @Sendable @escaping (String) -> any TranscriptSink,
        cacheLimit: Int,
        clock: any ClockProviding
    ) {
        self.translator = translator
        self.sinkFactory = sinkFactory
        self.clock = clock
        self.cache = TranslationCache(limit: cacheLimit)

        var cont: AsyncStream<TranslationEvent>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: Public API

    /// Forward-only target selection. Existing per-target files continue to accept lines
    /// from *now on* for targets that stay active; targets removed here stop receiving lines
    /// from the next handleFinal call. Backlog is never re-translated (docs §04, test 4.11).
    func setTargets(_ targets: [String]) async {
        // Close sinks whose targets were removed.
        for target in activeTargets where !targets.contains(target) {
            await sinks[target]?.close()
            sinks[target] = nil
        }
        // Open new sinks (idempotent: existing stay).
        for target in targets where sinks[target] == nil {
            sinks[target] = sinkFactory(target)
        }
        activeTargets = targets
    }

    func handleFinal(_ line: TranscriptLine) async {
        for target in activeTargets {
            await handle(line, target: target)
        }
    }

    func close() async {
        for sink in sinks.values {
            await sink.close()
        }
        sinks.removeAll()
        activeTargets.removeAll()
        continuation.finish()
    }

    func discardAll() async throws {
        for sink in sinks.values {
            try? await sink.discard()
        }
        sinks.removeAll()
        activeTargets.removeAll()
    }

    // MARK: Internals

    private func handle(_ line: TranscriptLine, target: String) async {
        // Same-language: copy, don't round-trip (test 4.3).
        if line.language == target {
            let copied = TranscriptLine(
                id: line.id,
                time: line.time,
                language: target,
                text: line.text,
                confidence: line.confidence
            )
            try? await sinks[target]?.write(copied)
            continuation.yield(.skipped(source: line, target: target, reason: .sameLanguage))
            return
        }

        // Cache lookup (tests 4.4, 4.5).
        if let cached = cache.get(text: line.text, from: line.language, to: target) {
            let translatedLine = TranscriptLine(
                time: line.time,
                language: target,
                text: cached,
                confidence: line.confidence
            )
            try? await sinks[target]?.write(translatedLine)
            continuation.yield(.translated(source: line, target: target, text: cached))
            return
        }

        // Translate — failure isolated per target (tests 4.6, 4.7).
        do {
            let text = try await translator.translate(line.text, from: line.language, to: target)
            cache.put(text: line.text, from: line.language, to: target, value: text)
            let translatedLine = TranscriptLine(
                time: line.time,
                language: target,
                text: text,
                confidence: line.confidence
            )
            try? await sinks[target]?.write(translatedLine)
            continuation.yield(.translated(source: line, target: target, text: text))
        } catch {
            continuation.yield(.failed(
                source: line,
                target: target,
                failure: .backendFailed(String(describing: error))
            ))
        }
    }
}
