import Foundation
@testable import SayAgain

final class ScriptedTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {

    enum Outcome: Sendable {
        case result(EngineResult)
        case failure(Error)
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    private let lock = NSLock()
    private var queue: [Outcome] = []
    private(set) var calls: [(sampleCount: Int, language: String?)] = []

    init(_ initial: [Outcome] = []) {
        self.queue = initial
    }

    func enqueue(_ outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        queue.append(outcome)
    }

    /// Convenience — enqueue a single-segment successful result.
    func enqueueText(_ text: String, language: String? = nil, confidence: Double = 1.0) {
        enqueue(.result(EngineResult(
            segments: [EngineSegment(text: text, confidence: confidence, noSpeechProbability: 0)],
            detectedLanguage: language,
            languageProbability: language == nil ? nil : 1.0
        )))
    }

    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult {
        lock.lock()
        calls.append((audio.samples.count, language))
        let next = queue.isEmpty ? nil : queue.removeFirst()
        lock.unlock()
        guard let next else {
            throw Failure(message: "no scripted outcome for call #\(calls.count)")
        }
        switch next {
        case .result(let r): return r
        case .failure(let e): throw e
        }
    }
}
