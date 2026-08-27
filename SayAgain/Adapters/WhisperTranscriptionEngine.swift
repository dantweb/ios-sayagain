#if SAYAGAINPLUS_TIER
import Foundation
import WhisperKit

/// Batch `TranscriptionEngine` backed by WhisperKit. Handles languages Apple's
/// `SpeechTranscriber` doesn't cover (ru, pl, ro, hu, th). The pipeline loads lazily on
/// first `transcribe(...)` call so app startup isn't blocked by model init.
///
/// WhisperKit expects 16 kHz mono Float32. The caller must supply audio in that format
/// (see `WhisperStreamingTranscriber`, which handles the AVAudioEngine → Float32 conversion).
nonisolated final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {

    /// Whisper model identifier — pulled from HuggingFace on first use if not present.
    let modelName: String

    private let lock = NSLock()
    private var pipeline: WhisperKit?

    init(modelName: String = "openai_whisper-base") {
        self.modelName = modelName
    }

    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult {
        let pipeline = try await ensurePipeline()

        // Constrain to a specific language when the caller has one; nil means whisper
        // auto-detects, which is what we want when multiple languages are configured.
        let options = DecodingOptions(
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        let results = try await pipeline.transcribe(audioArray: audio.samples, decodeOptions: options)

        // Combine all results — usually one but WhisperKit may split long audio.
        let combinedText = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let detected = results.first?.language

        let segments: [EngineSegment] = results.flatMap { result in
            result.segments.map { seg in
                EngineSegment(
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    // WhisperKit's avgLogprob is log-domain in [-∞, 0]. Map to a rough
                    // 0-1 confidence via exp; not a probability but a monotonic proxy that
                    // the coordinator's filter can use consistently.
                    confidence: Double(exp(seg.avgLogprob)),
                    noSpeechProbability: Double(seg.noSpeechProb)
                )
            }
        }

        return EngineResult(
            segments: segments.isEmpty
                ? [EngineSegment(text: combinedText, confidence: 1.0, noSpeechProbability: 0)]
                : segments,
            detectedLanguage: detected ?? language,
            languageProbability: detected != nil ? 1.0 : nil
        )
    }

    // MARK: - Pipeline lifecycle

    private func ensurePipeline() async throws -> WhisperKit {
        lock.lock()
        if let existing = pipeline {
            lock.unlock()
            return existing
        }
        lock.unlock()

        // Load off the caller's actor context. WhisperKit downloads the model on first use.
        let created = try await WhisperKit(model: modelName)

        lock.lock()
        // Racing initialisers can happen if two `transcribe` calls hit us in parallel before
        // either finishes; keep whichever landed first.
        if let existing = pipeline {
            lock.unlock()
            return existing
        }
        pipeline = created
        lock.unlock()
        return created
    }
}
#endif
