#if SAYAGAINPLUS_TIER
import Foundation
import Testing
@testable import SayAgain

struct EndpointedTranscriberTests {

    // Silence-only input never produces a final.
    @Test func silenceProducesNoFinal() async throws {
        let engine = ScriptedTranscriptionEngine()
        let (transcriber, _) = Self.make(engine: engine)
        try await transcriber.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(transcriber.events, count: 0, timeoutSeconds: 0.4) }
        await transcriber.feed(silence(seconds: 1.0))
        let events = await collector.value

        #expect(events.isEmpty)
        #expect(engine.calls.isEmpty)
        await transcriber.stop()
    }

    // One utterance surrounded by silence → one final.
    @Test func toneBetweenSilencesYieldsOneFinal() async throws {
        let engine = ScriptedTranscriptionEngine()
        engine.enqueueText("hello world", language: "en", confidence: 0.9)

        let (transcriber, config) = Self.make(engine: engine)
        try await transcriber.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(transcriber.events, count: 1, timeoutSeconds: 2.0) }
        await transcriber.feed(
            silence(seconds: 1.0) + tone(seconds: 1.0) + silence(seconds: config.silenceHangoverSeconds + 0.2)
        )
        let events = await collector.value

        let finals = Self.finalisedLines(from: events)
        #expect(finals.count == 1)
        #expect(finals.first?.text == "hello world")
        #expect(finals.first?.language == "en")
        await transcriber.stop()
    }

    // Two separated utterances → two finals.
    @Test func twoSeparatedUtterancesYieldTwoFinals() async throws {
        let engine = ScriptedTranscriptionEngine()
        engine.enqueueText("first", language: "en")
        engine.enqueueText("second", language: "en")

        let (transcriber, config) = Self.make(engine: engine)
        try await transcriber.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(transcriber.events, count: 2, timeoutSeconds: 3.0) }
        let hangover = config.silenceHangoverSeconds + 0.2
        await transcriber.feed(
            silence(seconds: 0.6)
            + tone(seconds: 0.8)
            + silence(seconds: hangover)
            + tone(seconds: 0.8)
            + silence(seconds: hangover)
        )
        let events = await collector.value

        let finals = Self.finalisedLines(from: events)
        #expect(finals.count == 2)
        #expect(finals[0].text == "first")
        #expect(finals[1].text == "second")
        await transcriber.stop()
    }

    // Engine failure surfaces as .failed but doesn't kill the transcriber.
    @Test func engineFailureYieldsFailedEvent() async throws {
        let engine = ScriptedTranscriptionEngine()
        engine.enqueue(.failure(ScriptedTranscriptionEngine.Failure(message: "boom")))
        engine.enqueueText("recovered", language: "en")

        let (transcriber, config) = Self.make(engine: engine)
        try await transcriber.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(transcriber.events, count: 2, timeoutSeconds: 3.0) }
        let hangover = config.silenceHangoverSeconds + 0.2
        await transcriber.feed(
            silence(seconds: 0.6)
            + tone(seconds: 0.8)
            + silence(seconds: hangover)
            + tone(seconds: 0.8)
            + silence(seconds: hangover)
        )
        let events = await collector.value

        let hasFailure = events.contains { if case .failed = $0 { true } else { false } }
        let recoveredFinals = Self.finalisedLines(from: events)
        #expect(hasFailure)
        #expect(recoveredFinals.contains { $0.text == "recovered" })
        await transcriber.stop()
    }

    // Stop flushes an in-progress utterance rather than dropping it.
    @Test func stopFlushesInProgress() async throws {
        let engine = ScriptedTranscriptionEngine()
        engine.enqueueText("interrupted", language: "en")

        let (transcriber, _) = Self.make(engine: engine)
        try await transcriber.start(spokenLanguages: ["en"])

        let collector = Task { await Self.collect(transcriber.events, count: 1, timeoutSeconds: 3.0) }
        // No hangover silence — utterance is still open when we call stop().
        await transcriber.feed(silence(seconds: 0.6) + tone(seconds: 0.8))
        await transcriber.stop()
        let events = await collector.value

        let finals = Self.finalisedLines(from: events)
        #expect(finals.count == 1)
        #expect(finals.first?.text == "interrupted")
    }

    // MARK: - Factory & helpers

    static func make(engine: any TranscriptionEngine, sampleRate: Double = 16_000)
    -> (EndpointedTranscriber, EndpointerConfig)
    {
        let config = EndpointerConfig(
            minSpeechSeconds: 0.4,
            maxSpeechSeconds: 12.0,
            silenceHangoverSeconds: 0.3,
            preRollSeconds: 0.25,
            noiseFloorAlpha: 0.05,
            speechThresholdFactor: 3.0
        )
        let transcriber = EndpointedTranscriber(
            engine: engine,
            language: "en",
            endpointerConfig: config,
            audioSampleRate: sampleRate,
            clock: FixedClock()
        )
        return (transcriber, config)
    }

    static func collect(
        _ stream: AsyncStream<TranscriptionEvent>,
        count: Int,
        timeoutSeconds: TimeInterval
    ) async -> [TranscriptionEvent] {
        // Race the stream against a timeout so tests don't hang if the transcriber
        // (a) never emits, or (b) emits fewer than `count` events.
        await withTaskGroup(of: [TranscriptionEvent].self) { group in
            group.addTask {
                var out: [TranscriptionEvent] = []
                for await event in stream {
                    out.append(event)
                    if out.count >= count { break }
                }
                return out
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            // If the stream task completed first, use its output; else the timeout won and we
            // return whatever we accumulated (which the collector-task also owns — but we
            // only see [] from timeout). Prefer the stream task's list.
            return first
        }
    }

    static func finalisedLines(from events: [TranscriptionEvent]) -> [TranscriptLine] {
        events.compactMap { event in
            if case .final(let line) = event { line } else { nil }
        }
    }
}

// MARK: - Synthetic audio

private func silence(seconds: Double, sampleRate: Double = 16_000) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * sampleRate))
}

private func tone(
    seconds: Double,
    sampleRate: Double = 16_000,
    frequency: Double = 440,
    amplitude: Float = 0.3
) -> [Float] {
    let count = Int(seconds * sampleRate)
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let t = Double(i) / sampleRate
        out[i] = amplitude * Float(sin(2 * .pi * frequency * t))
    }
    return out
}

private extension EndpointedTranscriber {
    /// Convenience: submit a `[Float]` buffer directly (tests build these inline).
    func feed(_ samples: [Float], sampleRate: Double = 16_000) async {
        await feed(AudioBuffer(
            samples: samples,
            sampleRate: sampleRate,
            channelCount: 1,
            timestamp: Date(timeIntervalSince1970: 0)
        ))
    }
}
#endif
