#if SAYAGAINPLUS_TIER
import Foundation
import WhisperKit

// WhisperKit's public class predates Swift Concurrency's Sendable annotations. Access to
// it in this file is fully serialised inside `WhisperTranscriptionEngine` (an actor) and
// the WhisperKit internals are documented as thread-safe, so we assert Sendable here
// rather than propagate warnings across every use site.
extension WhisperKit: @retroactive @unchecked Sendable {}

/// Batch `TranscriptionEngine` backed by WhisperKit. Handles languages Apple's
/// `SpeechTranscriber` doesn't cover (ru, pl, ro, hu, th). The pipeline loads lazily on
/// first `transcribe(...)` call so app startup isn't blocked by model init.
///
/// WhisperKit expects 16 kHz mono Float32. The caller must supply audio in that format
/// (see `WhisperStreamingTranscriber`, which handles the AVAudioEngine → Float32 conversion).
actor WhisperTranscriptionEngine: TranscriptionEngine {

    /// Whisper model identifier — pulled from HuggingFace on first use if not present.
    let modelName: String

    private var pipeline: WhisperKit?
    /// Coalesces concurrent first-time loads: only one WhisperKit init runs; callers await it.
    private var loadingTask: Task<WhisperKit, Error>?

    // `-small` (~244 MB, 244 M params) trades ~1.5-2× decode time vs `-base` (74 MB) for
    // markedly better accuracy on fast/accented speech — the main failure mode for our
    // non-English fallback set (ro, hu, pl, ru, th). See sprint/09 for the eval.
    init(modelName: String = "openai_whisper-small") {
        self.modelName = modelName
    }

    /// Force the pipeline to load into memory *and* prime the GPU by running one dummy
    /// decode. `WhisperKit(model:)` alone only memory-maps the weights — the actual GPU
    /// warm-up (CoreML compilation + Metal shader compilation) happens lazily on the
    /// first real `transcribe`. Without the dummy decode here, the second engine's
    /// warmup (MLX-LLM) races against Whisper's still-in-progress GPU init and produces
    /// mid-transcript stalls / Metal command buffer contention.
    func warmUp() async {
        guard ModelPack.whisperSTT.isInstalledOnDisk else {
            print("WhisperTranscriptionEngine: warmUp skipped — pack not installed")
            return
        }
        do {
            let pipeline = try await ensurePipeline()
            // ~0.5s of silence at 16 kHz mono. Cheapest input WhisperKit will accept while
            // still forcing full pipeline compilation. The result is discarded.
            let silence = [Float](repeating: 0, count: 8_000)
            print("WhisperTranscriptionEngine: warmUp — priming GPU with dummy decode")
            _ = try? await pipeline.transcribe(
                audioArray: silence,
                decodeOptions: DecodingOptions(
                    language: "en",
                    temperature: 0.0,
                    usePrefillPrompt: false,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    logProbThreshold: nil,
                    firstTokenLogProbThreshold: nil
                )
            )
            print("WhisperTranscriptionEngine: warmUp — GPU primed")
        } catch {
            print("WhisperTranscriptionEngine: warmUp failed — \(error)")
        }
    }

    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult {
        // Gate on user-driven install. Auto-download would silently pull ~74 MB the first
        // time transcription is requested; instead we surface a clear error so the UI can
        // route the user to Settings → Language Packs.
        guard ModelPack.whisperSTT.isInstalledOnDisk else {
            print("WhisperTranscriptionEngine: model not installed — throwing engineNotInstalled")
            throw EngineNotInstalledError(pack: .whisperSTT)
        }
        let seconds = Double(audio.samples.count) / audio.sampleRate
        print("WhisperTranscriptionEngine: transcribe requested (\(String(format: "%.2f", seconds))s, lang=\(language ?? "auto"))")
        let pipeline = try await ensurePipeline()
        print("WhisperTranscriptionEngine: pipeline ready, calling WhisperKit.transcribe")

        // Constrain to a specific language when the caller has one; nil means whisper
        // auto-detects, which is what we want when multiple languages are configured.
        //
        // Threshold tuning learned the hard way:
        //   - `firstTokenLogProbThreshold` and `logProbThreshold`: DISABLED. Whisper-base
        //     regularly trips these on short, quiet, or low-resource-language clips and
        //     bails out returning "!!!!" / "" — a lower-confidence real transcription is
        //     more useful.
        //   - `compressionRatioThreshold`: KEPT (default). Catches the "de la de la de la…"
        //     decoder-repetition loop where the model gets stuck emitting the same token
        //     forever. Its retry-at-higher-temperature strategy usually recovers.
        let options = DecodingOptions(
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            logProbThreshold: nil,
            firstTokenLogProbThreshold: nil
        )

        let results = try await pipeline.transcribe(audioArray: audio.samples, decodeOptions: options)
        let joined = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        print("WhisperTranscriptionEngine: got \(results.count) result(s), text=\"\(joined)\"")

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
        if let pipeline { return pipeline }
        if let loadingTask {
            print("WhisperTranscriptionEngine: awaiting in-flight load")
            return try await loadingTask.value
        }

        let name = modelName
        print("WhisperTranscriptionEngine: loading WhisperKit model '\(name)' — first-run downloads ~74MB")
        let task = Task { try await WhisperKit(model: name) }
        loadingTask = task
        do {
            let loaded = try await task.value
            print("WhisperTranscriptionEngine: model loaded")
            pipeline = loaded
            loadingTask = nil
            return loaded
        } catch {
            print("WhisperTranscriptionEngine: model load FAILED — \(error)")
            loadingTask = nil
            throw error
        }
    }
}
#endif
