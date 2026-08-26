import Foundation

nonisolated struct Endpointer: Sendable {

    // MARK: Configuration
    private let config: EndpointerConfig
    private let clock: any ClockProviding
    private let sampleRate: Double

    // MARK: State
    private enum State: Sendable {
        case idle
        case speaking(startTime: Date)
    }
    private var state: State = .idle

    // Adaptive noise floor (RMS units, 0…1).
    private var noiseFloor: Float = 0

    // Warmup lets the noise floor learn the ambient level before we trigger.
    private static let warmupSeconds: Double = 0.5
    private var warmupSamplesRemaining: Int

    // Pre-roll buffer: audio kept while idle so the leading consonant survives.
    private var preRoll: [Float] = []

    // For the current utterance:
    //   voicedSamples — the fix (Defect 1). minSpeechSeconds is asserted against THIS,
    //   not against utteranceSamples which is padded with pre-roll + trailing silence.
    private var voicedSamples: [Float] = []
    private var utteranceSamples: [Float] = []
    private var trailingSilenceSamples: Int = 0

    // MARK: Init

    init(config: EndpointerConfig, clock: any ClockProviding, sampleRate: Double) {
        self.config = config
        self.clock = clock
        self.sampleRate = sampleRate
        self.warmupSamplesRemaining = max(0, Int(Self.warmupSeconds * sampleRate))
    }

    // MARK: Derived limits

    private var preRollLimit: Int      { max(0, Int(config.preRollSeconds        * sampleRate)) }
    private var hangoverLimit: Int     { max(0, Int(config.silenceHangoverSeconds * sampleRate)) }
    private var minSpeechLimit: Int    { max(0, Int(config.minSpeechSeconds      * sampleRate)) }
    private var maxSpeechLimit: Int    { max(0, Int(config.maxSpeechSeconds      * sampleRate)) }

    // MARK: Public API

    mutating func feed(_ buffer: AudioBuffer) -> [Utterance] {
        var output: [Utterance] = []
        let frameSize = max(1, Int(0.02 * sampleRate))   // 20 ms frames
        var index = 0
        while index < buffer.samples.count {
            let end = min(index + frameSize, buffer.samples.count)
            let frame = Array(buffer.samples[index..<end])
            index = end

            let rms = Self.rms(frame)
            let inWarmup = warmupSamplesRemaining > 0
            let threshold = max(noiseFloor * Float(config.speechThresholdFactor), 1e-6)
            let isVoiced = !inWarmup && rms > threshold

            if inWarmup || !isVoiced {
                updateNoiseFloor(with: rms)
            }
            warmupSamplesRemaining = max(0, warmupSamplesRemaining - frame.count)

            switch state {
            case .idle:
                if isVoiced {
                    state = .speaking(startTime: buffer.timestamp)
                    utteranceSamples = preRoll
                    utteranceSamples.append(contentsOf: frame)
                    voicedSamples = frame
                    trailingSilenceSamples = 0
                    preRoll.removeAll(keepingCapacity: true)
                } else {
                    appendPreRoll(frame)
                }

            case .speaking(let startTime):
                utteranceSamples.append(contentsOf: frame)
                if isVoiced {
                    voicedSamples.append(contentsOf: frame)
                    trailingSilenceSamples = 0
                } else {
                    trailingSilenceSamples += frame.count
                }

                // Force-split (measure against voiced audio, not the padded stream — Defect 1 applies here too).
                if voicedSamples.count >= maxSpeechLimit {
                    if let u = closeUtterance(startTime: startTime, force: true) {
                        output.append(u)
                    }
                    continue
                }

                if trailingSilenceSamples >= hangoverLimit {
                    if let u = closeUtterance(startTime: startTime, force: false) {
                        output.append(u)
                    }
                }
            }
        }
        return output
    }

    mutating func flush() -> Utterance? {
        switch state {
        case .idle:
            return nil
        case .speaking(let startTime):
            // Flush honours the user — don't apply minSpeechSeconds. Last words survive.
            return closeUtterance(startTime: startTime, force: true)
        }
    }

    // MARK: Internals

    private mutating func closeUtterance(startTime: Date, force: Bool) -> Utterance? {
        defer { resetToIdle() }
        // THE FIX: gate on voiced audio, not the padded utterance.
        if !force && voicedSamples.count < minSpeechLimit {
            return nil
        }
        let samples = utteranceSamples
        let end = clock.now()
        let audio = AudioBuffer(
            samples: samples,
            sampleRate: sampleRate,
            channelCount: 1,
            timestamp: startTime
        )
        return Utterance(audio: audio, start: startTime, end: end)
    }

    private mutating func resetToIdle() {
        state = .idle
        preRoll.removeAll(keepingCapacity: true)
        voicedSamples.removeAll(keepingCapacity: true)
        utteranceSamples.removeAll(keepingCapacity: true)
        trailingSilenceSamples = 0
    }

    private mutating func appendPreRoll(_ frame: [Float]) {
        preRoll.append(contentsOf: frame)
        let excess = preRoll.count - preRollLimit
        if excess > 0 {
            preRoll.removeFirst(excess)
        }
    }

    private mutating func updateNoiseFloor(with rms: Float) {
        let alpha = Float(config.noiseFloorAlpha)
        if noiseFloor == 0 {
            noiseFloor = rms                                     // first sample seeds the floor
        } else {
            noiseFloor = (1 - alpha) * noiseFloor + alpha * rms  // EMA
        }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        return Float((sum / Double(samples.count)).squareRoot())
    }
}
