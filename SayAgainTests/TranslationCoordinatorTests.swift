import Foundation
import Testing
@testable import SayAgain

struct TranslationCoordinatorTests {

    // MARK: 4.1 & 4.2 — one output per target; every line reaches every target
    @Test func everyLineReachesEveryTarget() async throws {
        let (coordinator, translator, sinks) = Self.make()
        await coordinator.setTargets(["es", "fr"])

        translator.set("hola", for: "hello", from: "en", to: "es")
        translator.set("bonjour", for: "hello", from: "en", to: "fr")
        translator.set("adiós", for: "bye", from: "en", to: "es")
        translator.set("au revoir", for: "bye", from: "en", to: "fr")

        await coordinator.handleFinal(TranscriptLine(time: Date(timeIntervalSince1970: 1), language: "en", text: "hello"))
        await coordinator.handleFinal(TranscriptLine(time: Date(timeIntervalSince1970: 2), language: "en", text: "bye"))

        #expect(sinks.sink(for: "es")?.lines.count == 2)
        #expect(sinks.sink(for: "fr")?.lines.count == 2)
        #expect(sinks.sink(for: "es")?.lines.first?.text == "hola")
        #expect(sinks.sink(for: "fr")?.lines.last?.text == "au revoir")
    }

    // MARK: 4.3 — line already in target language is copied, not round-tripped
    @Test func sameLanguageIsCopiedNotTranslated() async throws {
        let (coordinator, translator, sinks) = Self.make()
        await coordinator.setTargets(["en"])

        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "hello world"))

        #expect(translator.calls.isEmpty, "translator must not be called when source == target")
        #expect(sinks.sink(for: "en")?.lines.count == 1)
        #expect(sinks.sink(for: "en")?.lines.first?.text == "hello world")
    }

    // MARK: 4.4 — repeated text translated once (cache hit)
    @Test func repeatedTextTranslatedOnce() async throws {
        let (coordinator, translator, sinks) = Self.make()
        await coordinator.setTargets(["es"])
        translator.set("hola", for: "hello", from: "en", to: "es")

        await coordinator.handleFinal(TranscriptLine(time: Date(timeIntervalSince1970: 1), language: "en", text: "hello"))
        await coordinator.handleFinal(TranscriptLine(time: Date(timeIntervalSince1970: 2), language: "en", text: "hello"))

        #expect(translator.calls.count == 1)
        #expect(sinks.sink(for: "es")?.lines.count == 2)
    }

    // MARK: 4.5 — cache eviction re-translates beyond the limit
    @Test func cacheEvictionReTranslates() async throws {
        let (coordinator, translator, sinks) = Self.make(cacheLimit: 2)
        await coordinator.setTargets(["es"])
        translator.set("A", for: "a", from: "en", to: "es")
        translator.set("B", for: "b", from: "en", to: "es")
        translator.set("C", for: "c", from: "en", to: "es")

        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "a"))
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "b"))
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "c"))
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "a"))  // evicted → re-translate

        #expect(translator.calls.count == 4)
        #expect(sinks.sink(for: "es")?.lines.count == 4)
    }

    // MARK: 4.6 & 4.7 — failing target loses one line; others unaffected; no propagation
    @Test func failingTargetIsIsolated() async throws {
        let (coordinator, translator, sinks) = Self.make()
        await coordinator.setTargets(["es", "fr"])
        translator.forceFailure(forTarget: "es")
        translator.set("bonjour", for: "hello", from: "en", to: "fr")

        // Must not throw or hang.
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "hello"))

        #expect((sinks.sink(for: "es")?.lines ?? []).isEmpty)
        #expect(sinks.sink(for: "fr")?.lines.count == 1)
        #expect(sinks.sink(for: "fr")?.lines.first?.text == "bonjour")
    }

    // MARK: 4.11 — changing target mid-session translates subsequent lines only
    @Test func changingTargetMidSessionAppliesForwardOnly() async throws {
        let (coordinator, translator, sinks) = Self.make()
        translator.set("hola", for: "hello", from: "en", to: "es")
        translator.set("bonjour", for: "hello", from: "en", to: "fr")
        translator.set("mundo", for: "world", from: "en", to: "es")
        translator.set("monde", for: "world", from: "en", to: "fr")

        await coordinator.setTargets(["es"])
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "hello"))

        await coordinator.setTargets(["fr"])
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "world"))

        // 'hello' → es only. 'world' → fr only. No re-translation.
        #expect(sinks.sink(for: "es")?.lines.count == 1)
        #expect(sinks.sink(for: "es")?.lines.first?.text == "hola")
        #expect(sinks.sink(for: "fr")?.lines.count == 1)
        #expect(sinks.sink(for: "fr")?.lines.first?.text == "monde")
    }

    // MARK: 4.12 — selecting None (empty targets) mid-session stops translating forward
    @Test func selectingEmptyTargetsStopsTranslating() async throws {
        let (coordinator, translator, sinks) = Self.make()
        translator.set("hola", for: "hello", from: "en", to: "es")

        await coordinator.setTargets(["es"])
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "hello"))

        await coordinator.setTargets([])
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "world"))

        #expect(sinks.sink(for: "es")?.lines.count == 1, "the second line must not be translated")
        #expect(translator.calls.count == 1)
    }

    // discardAll clears every per-target sink (used by Cancel / Clean).
    @Test func discardAllClearsEveryTargetSink() async throws {
        let (coordinator, _, sinks) = Self.make()
        await coordinator.setTargets(["es", "fr"])
        await coordinator.handleFinal(TranscriptLine(time: Date(), language: "en", text: "hello"))

        try await coordinator.discardAll()

        #expect((sinks.sink(for: "es")?.discardCallCount ?? 0) >= 1)
        #expect((sinks.sink(for: "fr")?.discardCallCount ?? 0) >= 1)
    }

    // MARK: - Factory

    static func make(cacheLimit: Int = 512) -> (TranslationCoordinator, StubTranslator, SinkRecorder) {
        let translator = StubTranslator()
        let recorder = SinkRecorder()
        let coordinator = TranslationCoordinator(
            translator: translator,
            sinkFactory: { target in recorder.factory(for: target) },
            cacheLimit: cacheLimit,
            clock: FixedClock()
        )
        return (coordinator, translator, recorder)
    }
}
