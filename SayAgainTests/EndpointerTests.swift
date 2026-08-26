import Foundation
import Testing
@testable import SayAgain

struct EndpointerTests {

    // MARK: - 2.1
    @Test func silenceAloneProducesNoUtterance() {
        var endpointer = Self.makeEndpointer()
        let result = endpointer.feed(buffer(silence(seconds: 3.0)))
        #expect(result.isEmpty)
        #expect(endpointer.flush() == nil)
    }

    // MARK: - 2.2
    @Test func toneBetweenSilencesYieldsExactlyOneUtterance() {
        let config = Self.loadConfig()
        var endpointer = Self.makeEndpointer()
        let samples =
            silence(seconds: 1.0)
            + tone(seconds: 1.0)
            + silence(seconds: config.endpointer.silenceHangoverSeconds + 0.1)
        let result = endpointer.feed(buffer(samples))
        #expect(result.count == 1)
    }

    // MARK: - 2.3
    @Test func twoSeparatedTonesYieldTwoUtterances() {
        let config = Self.loadConfig()
        var endpointer = Self.makeEndpointer()
        let hangoverGap = config.endpointer.silenceHangoverSeconds + 0.2
        let samples =
            silence(seconds: 1.0)
            + tone(seconds: 1.0)
            + silence(seconds: hangoverGap)
            + tone(seconds: 1.0)
            + silence(seconds: hangoverGap)
        let result = endpointer.feed(buffer(samples))
        #expect(result.count == 2)
    }

    // MARK: - 2.4 — the FIX (Defect 1)
    @Test func shortBlipIsDiscardedAgainstVoicedAudioGate() {
        let config = Self.loadConfig()
        var endpointer = Self.makeEndpointer()
        let blipSeconds = 0.15
        #expect(blipSeconds < config.endpointer.minSpeechSeconds)   // preconditon
        let samples =
            silence(seconds: 1.0)
            + tone(seconds: blipSeconds)
            + silence(seconds: config.endpointer.silenceHangoverSeconds + 0.1)
        let result = endpointer.feed(buffer(samples))
        #expect(result.isEmpty, "0.15s blip must be discarded — the voiced-audio gate")
    }

    // MARK: - 2.5
    @Test func speechBeyondMaxIsForceSplitAndSplitKeepsAudio() {
        let config = Self.loadConfig()
        var endpointer = Self.makeEndpointer()
        let toneDuration = config.endpointer.maxSpeechSeconds + 3.0
        let samples = silence(seconds: 0.6) + tone(seconds: toneDuration)
        let feedResult = endpointer.feed(buffer(samples))
        let flushed = endpointer.flush()

        #expect(feedResult.count >= 1)
        #expect(flushed != nil)
        for u in feedResult {
            #expect(!u.audio.samples.isEmpty)
        }
        if let f = flushed {
            #expect(!f.audio.samples.isEmpty)
        }
    }

    // MARK: - 2.6
    @Test func preRollMakesUtteranceStartBeforeOnset() {
        let config = Self.loadConfig()
        var endpointer = Self.makeEndpointer()
        let samples =
            silence(seconds: 1.0)
            + tone(seconds: 0.6)
            + silence(seconds: config.endpointer.silenceHangoverSeconds + 0.1)
        let result = endpointer.feed(buffer(samples))
        #expect(result.count == 1)
        guard let u = result.first else { return }
        let preRollSampleCount = Int(config.endpointer.preRollSeconds * Self.sampleRate)
        #expect(u.audio.samples.count > preRollSampleCount, "utterance must include leading pre-roll audio")
        let leading = Array(u.audio.samples.prefix(preRollSampleCount))
        let leadingRMS = Self.rms(leading)
        #expect(leadingRMS < 0.02, "leading pre-roll must be silence")
    }

    // MARK: - 2.7
    @Test func flushReturnsInProgressAndThenNothing() {
        var endpointer = Self.makeEndpointer()
        // Feed speech WITHOUT the trailing hangover — utterance stays open.
        let samples = silence(seconds: 0.6) + tone(seconds: 1.0)
        let feedResult = endpointer.feed(buffer(samples))
        #expect(feedResult.isEmpty)
        let flushed = endpointer.flush()
        #expect(flushed != nil)
        let flushedAgain = endpointer.flush()
        #expect(flushedAgain == nil)
    }

    // MARK: - 2.8
    @Test func steadyBackgroundNoiseNeverTriggers() {
        var endpointer = Self.makeEndpointer()
        var rng = SeededRandom(seed: 0xC0FFEE)
        let samples = noise(seconds: 5.0, amplitude: 0.015, rng: &rng)
        let result = endpointer.feed(buffer(samples))
        #expect(result.isEmpty)
        #expect(endpointer.flush() == nil)
    }

    // MARK: - 2.9
    @Test func lowerSensitivityDetectsQuietSpeechHigherMisses() {
        let base = Self.loadConfig().endpointer
        let sensitiveConfig = EndpointerConfig(
            minSpeechSeconds: base.minSpeechSeconds,
            maxSpeechSeconds: base.maxSpeechSeconds,
            silenceHangoverSeconds: base.silenceHangoverSeconds,
            preRollSeconds: base.preRollSeconds,
            noiseFloorAlpha: base.noiseFloorAlpha,
            speechThresholdFactor: 1.5           // more sensitive
        )
        let insensitiveConfig = EndpointerConfig(
            minSpeechSeconds: base.minSpeechSeconds,
            maxSpeechSeconds: base.maxSpeechSeconds,
            silenceHangoverSeconds: base.silenceHangoverSeconds,
            preRollSeconds: base.preRollSeconds,
            noiseFloorAlpha: base.noiseFloorAlpha,
            speechThresholdFactor: 30.0          // less sensitive
        )

        // Ambient noise + quiet tone
        var rng1 = SeededRandom(seed: 1)
        var rng2 = SeededRandom(seed: 1)
        let ambient1 = noise(seconds: 1.0, amplitude: 0.008, rng: &rng1)
        let ambient2 = noise(seconds: 1.0, amplitude: 0.008, rng: &rng2)
        let quietTone = tone(seconds: 1.0, amplitude: 0.05)
        let hangoverSilence = silence(seconds: base.silenceHangoverSeconds + 0.1)

        var sensitiveEndpointer = Endpointer(config: sensitiveConfig, clock: FixedClock(), sampleRate: Self.sampleRate)
        var insensitiveEndpointer = Endpointer(config: insensitiveConfig, clock: FixedClock(), sampleRate: Self.sampleRate)

        let sensitiveResult = sensitiveEndpointer.feed(buffer(ambient1 + quietTone + hangoverSilence))
        let insensitiveResult = insensitiveEndpointer.feed(buffer(ambient2 + quietTone + hangoverSilence))

        #expect(sensitiveResult.count >= 1, "low threshold factor must catch quiet speech")
        #expect(insensitiveResult.isEmpty, "high threshold factor must miss quiet speech")
    }
}

// MARK: - Test helpers

extension EndpointerTests {

    static let sampleRate: Double = 16_000

    static func loadConfig() -> SayAgainConfiguration {
        try! SayAgainConfiguration.loadFromBundle(bundle: .main)
    }

    static func makeEndpointer() -> Endpointer {
        let config = loadConfig().endpointer
        return Endpointer(config: config, clock: FixedClock(), sampleRate: sampleRate)
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        return Float((sum / Double(samples.count)).squareRoot())
    }
}

// MARK: - Synthetic audio

private func silence(seconds: Double, sampleRate: Double = EndpointerTests.sampleRate) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * sampleRate))
}

private func tone(
    seconds: Double,
    sampleRate: Double = EndpointerTests.sampleRate,
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

private func noise(
    seconds: Double,
    sampleRate: Double = EndpointerTests.sampleRate,
    amplitude: Float,
    rng: inout SeededRandom
) -> [Float] {
    let count = Int(seconds * sampleRate)
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        out[i] = rng.nextFloat(in: -amplitude...amplitude)
    }
    return out
}

private func buffer(_ samples: [Float], sampleRate: Double = EndpointerTests.sampleRate) -> AudioBuffer {
    AudioBuffer(samples: samples, sampleRate: sampleRate, channelCount: 1, timestamp: Date(timeIntervalSince1970: 0))
}

// Deterministic PRNG so noise-based tests don't flake.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let u = Float(state & 0xFFFFFF) / Float(0xFFFFFF)
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}
