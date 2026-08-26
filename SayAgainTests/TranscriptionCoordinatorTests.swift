import Foundation
import Testing
@testable import SayAgain

struct TranscriptionCoordinatorTests {

    // MARK: 3.1 — a scripted final becomes a TranscriptLine (display + sink)
    @Test func scriptedFinalBecomesTranscriptLineOnDisplayAndSink() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let expectedTime = Date(timeIntervalSince1970: 1_700_000_000)
        let collector = Task { await Self.collect(coordinator.stream, count: 1) }
        transcriber.emit(.final(TranscriptLine(time: expectedTime, language: "en", text: "hello world")))
        let events = await collector.value

        let finalised = Self.finalisedLines(from: events)
        #expect(finalised.count == 1)
        #expect(finalised.first?.text == "hello world")
        #expect(finalised.first?.language == "en")
        #expect(finalised.first?.time == expectedTime)

        await coordinator.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(sink.lines.count == 1)
    }

    // MARK: 3.11 — volatile followed by final yields ONE finalised line
    @Test func volatileFollowedByFinalYieldsOneFinalisedLine() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(coordinator.stream, count: 3) }
        transcriber.emit(.volatile("hello"))
        transcriber.emit(.volatile("hello w"))
        transcriber.emit(.final(TranscriptLine(time: Date(), language: "en", text: "hello world")))
        let events = await collector.value

        #expect(Self.finalisedLines(from: events).count == 1)
        #expect(Self.volatileUpdates(from: events).count == 2)

        await coordinator.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(sink.lines.count == 1)
    }

    // MARK: 3.12 — volatile is NEVER written to the sink
    @Test func volatileIsNeverWrittenToSink() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(coordinator.stream, count: 2) }
        transcriber.emit(.volatile("draft"))
        transcriber.emit(.volatile("draft two"))
        _ = await collector.value

        #expect(sink.lines.isEmpty)

        await coordinator.stop()
    }

    // MARK: 3.10 — a .failed event doesn't stop the session; subsequent .final still lands
    @Test func failedEventDoesNotStopSession() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(coordinator.stream, count: 2) }
        transcriber.emit(.failed(.engineFailed("boom")))
        transcriber.emit(.final(TranscriptLine(time: Date(), language: "en", text: "after failure")))
        let events = await collector.value

        let hasFailure = events.contains { if case .failure = $0 { true } else { false } }
        #expect(hasFailure)

        let finalised = Self.finalisedLines(from: events)
        #expect(finalised.first?.text == "after failure")

        await coordinator.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(sink.lines.count == 1)
    }

    // MARK: 3.14 — stopping mid-phrase finalises the volatile text
    @Test func stoppingMidPhraseFinalisesVolatile() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let volatileCollector = Task { await Self.collect(coordinator.stream, count: 1) }
        transcriber.emit(.volatile("last unfinished words"))
        _ = await volatileCollector.value

        await coordinator.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(sink.lines.count == 1)
        #expect(sink.lines.first?.text == "last unfinished words")
    }

    // Cancel discards volatile and calls discard on the sink.
    @Test func cancelDiscardsVolatileAndSink() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator()
        try await coordinator.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(coordinator.stream, count: 1) }
        transcriber.emit(.volatile("throwaway"))
        _ = await collector.value

        await coordinator.cancel()
        try? await Task.sleep(nanoseconds: 30_000_000)

        #expect(sink.lines.isEmpty)
        #expect(sink.discardCallCount == 1)
    }

    // Hallucination filter is applied to finalised lines.
    @Test func hallucinationInFinalisedLineIsFiltered() async throws {
        let (coordinator, transcriber, sink) = await Self.makeCoordinator(blocklist: ["thanks for watching."])
        try await coordinator.start(spokenLanguages: ["en"])

        // Expect exactly ONE finalised event: the first survives (mixed → "hello world");
        // the second is pure hallucination and produces no display event and no sink write.
        let collector = Task { await Self.collect(coordinator.stream, count: 1) }
        transcriber.emit(.final(TranscriptLine(time: Date(), language: "en", text: "thanks for watching hello world")))
        transcriber.emit(.final(TranscriptLine(time: Date(), language: "en", text: "Thanks for watching.")))
        let events = await collector.value

        let finalised = Self.finalisedLines(from: events)
        #expect(finalised.count == 1)
        #expect(finalised.first?.text == "hello world")

        // Give the second event's async handling time to complete before we assert on the sink.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(sink.lines.count == 1)

        await coordinator.stop()
    }

    // MARK: - Helpers

    static func makeCoordinator(blocklist: [String] = []) async -> (TranscriptionCoordinator, ScriptedStreamingTranscriber, InMemoryTranscriptSink) {
        let transcriber = ScriptedStreamingTranscriber()
        let sink = InMemoryTranscriptSink()
        let policy = TranscriptionPolicy(
            allowedLanguages: ["en"],
            hallucinationBlocklist: blocklist,
            minConfidence: 0.3,
            maxNoSpeechProbability: 0.7
        )
        let coordinator = TranscriptionCoordinator(
            transcriber: transcriber,
            sink: sink,
            policy: policy,
            clock: FixedClock()
        )
        return (coordinator, transcriber, sink)
    }

    static func collect(_ stream: AsyncStream<DisplayEvent>, count: Int) async -> [DisplayEvent] {
        var out: [DisplayEvent] = []
        for await event in stream {
            out.append(event)
            if out.count >= count { break }
        }
        return out
    }

    static func finalisedLines(from events: [DisplayEvent]) -> [TranscriptLine] {
        events.compactMap { event in
            if case .finalised(let line) = event { line } else { nil }
        }
    }

    static func volatileUpdates(from events: [DisplayEvent]) -> [String] {
        events.compactMap { event in
            if case .volatileUpdated(let text) = event { text } else { nil }
        }
    }
}
