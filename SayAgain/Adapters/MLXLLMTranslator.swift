#if SAYAGAINPLUS_TIER
import Foundation
import Hub
import MLX
import MLXLMCommon

/// Offline translator backed by a quantized on-device LLM (MLX). Handles language pairs
/// Apple's `Translation` framework doesn't cover — currently `ro`, `hu`, `th` — via prompting.
///
/// The model downloads once on first use (~1 GB for Qwen-2.5-1.5B-Instruct-4bit) and is
/// cached under Application Support. Every translation after that runs fully offline.
///
/// Latency: 5-15 seconds per short sentence on iPhone 14. This is a fallback for locales
/// with no better path; users should expect noticeable delay compared to Apple Translation.
actor MLXLLMTranslator: Translating {

    private let modelId: String
    /// `ModelContainer` is an actor around the loaded weights + tokenizer; safe to hold
    /// across suspensions and share between concurrent translate calls.
    private var container: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?
    /// Serial chain: each new translation waits for the previous one to finish.
    /// This is required because MLX-Swift's Metal command buffer is not safe for
    /// concurrent inference on the same `ModelContainer` — parallel `session.respond`
    /// calls trigger `_MTLCommandBuffer addCompletedHandler` assertions and crash the
    /// app. Actor isolation alone doesn't prevent this: each `await` inside `translate`
    /// releases the actor and lets the next queued call slip in.
    private var lastInference: Task<String, Error>?

    /// Default: Qwen-2.5-1.5B-Instruct 4-bit MLX. Small enough to fit on an iPhone 14
    /// (~1 GB), good enough multilingual coverage for our fallback set.
    init(modelId: String = "mlx-community/Qwen2.5-1.5B-Instruct-4bit") {
        self.modelId = modelId
    }

    /// Preload the ~1 GB Qwen model into memory ahead of the first `translate` call.
    /// Called from `SessionViewModel.start()` in parallel with the mic setup so users
    /// don't wait for the model load to visibly begin only *after* they've said a full
    /// sentence.
    func warmUp() async {
        guard ModelPack.llmMT.isInstalledOnDisk else {
            print("MLXLLMTranslator: warmUp skipped — pack not installed")
            return
        }
        do {
            _ = try await ensureModel()
        } catch {
            print("MLXLLMTranslator: warmUp failed — \(error)")
        }
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        // Same gate as Whisper: the LLM pack is ~1 GB, so auto-downloading on first use
        // is a bad surprise. Refuse until Settings → Language Packs has installed it.
        guard ModelPack.llmMT.isInstalledOnDisk else {
            throw EngineNotInstalledError(pack: .llmMT)
        }
        print("MLXLLMTranslator: translate(\(source)→\(target)) requested, chars=\(text.count)")

        // Chain onto the previous inference so `respond()` calls are strictly serial.
        // Each caller stores the new task as `lastInference` before awaiting it, so the
        // NEXT translate call will wait behind us.
        let previous = lastInference
        let task = Task<String, Error> { [previous, text, source, target] in
            _ = try? await previous?.value
            return try await self.performInference(text: text, source: source, target: target)
        }
        lastInference = task
        return try await task.value
    }

    private func performInference(text: String, source: String, target: String) async throws -> String {
        let model = try await ensureModel()
        print("MLXLLMTranslator: model ready, starting ChatSession")
        let session = ChatSession(model)
        let prompt = Self.buildPrompt(text: text, source: source, target: target)
        let raw = try await session.respond(to: prompt)
        print("MLXLLMTranslator: got response, chars=\(raw.count)")
        // Release MLX's per-inference Metal cache back to the OS. Without this each
        // ChatSession's KV-cache buffers accumulate across calls and, on a 6 GB iPhone,
        // jetsam kills the app somewhere around the 15-20th translation (log stops
        // silently right after "starting ChatSession"). This is the same call MLX
        // recommends for memory-constrained loops.
        MLX.GPU.clearCache()
        return Self.cleanResponse(raw)
    }

    // MARK: - Model lifecycle

    private func ensureModel() async throws -> ModelContainer {
        if let container {
            print("MLXLLMTranslator: reusing loaded container")
            return container
        }
        if let loadingTask {
            print("MLXLLMTranslator: awaiting in-flight model load")
            return try await loadingTask.value
        }

        let id = modelId
        // MLX's default `defaultHubApi` uses ~/Library/Caches/huggingface, but our
        // `ModelDownloadManager` (and WhisperKit) unpack to Documents/huggingface. Passing
        // a Hub pointed at the same base makes `loadModelContainer` find the files we
        // already downloaded instead of silently trying to re-fetch them from HuggingFace.
        let hub = HubApi(downloadBase: ModelPack.huggingFaceBase)
        print("MLXLLMTranslator: loading '\(id)' from \(ModelPack.huggingFaceBase.path)")
        let task = Task {
            try await loadModelContainer(hub: hub, id: id, progressHandler: { progress in
                if progress.fractionCompleted > 0 && progress.fractionCompleted < 1 {
                    print("MLXLLMTranslator: load progress \(Int(progress.fractionCompleted * 100))%")
                }
            })
        }
        loadingTask = task
        do {
            let loaded = try await task.value
            print("MLXLLMTranslator: model container loaded")
            container = loaded
            loadingTask = nil
            return loaded
        } catch {
            print("MLXLLMTranslator: model load FAILED — \(error)")
            loadingTask = nil
            throw error
        }
    }

    // MARK: - Prompt

    private static func buildPrompt(text: String, source: String, target: String) -> String {
        let src = languageName(source)
        let tgt = languageName(target)
        let script = scriptHint(for: target)
        // Qwen-1.5B is small and drifts to English or echoes the input when the prompt is
        // vague. Being explicit about the OUTPUT language and script (Cyrillic for ru, etc.)
        // meaningfully reduces both failure modes in our testing.
        return """
        You are a professional translator. Translate the text from \(src) to \(tgt).

        Rules:
        - Write the output ONLY in \(tgt)\(script).
        - Do NOT output English unless \(tgt) is English.
        - Do NOT repeat, echo, or include any \(src) words.
        - Do NOT add explanations, labels, prefixes, or quotes.
        - Output the translation and nothing else.

        \(src): \(text)
        \(tgt):
        """
    }

    /// Hard-coded script hint per target-language ISO code. Bare English language names
    /// aren't enough for a 1.5B model — telling it "using Cyrillic script" is what stops
    /// Qwen from producing a Latin-transliterated Russian response.
    private static func scriptHint(for target: String) -> String {
        switch target {
        case "ru", "uk", "be", "bg", "sr":  return " using Cyrillic script"
        case "ja":                          return " using Japanese script (Hiragana/Katakana/Kanji)"
        case "zh":                          return " using Chinese characters (Hanzi)"
        case "ko":                          return " using Korean Hangul"
        case "ar":                          return " using Arabic script"
        case "th":                          return " using Thai script"
        case "he":                          return " using Hebrew script"
        default:                            return ""  // Latin-script targets don't need the hint
        }
    }

    /// `Locale.current` gives the user's UI language; we want the language name in English
    /// so the LLM prompt is unambiguous regardless of the user's locale.
    private static let englishLocale = Locale(identifier: "en_US")

    private static func languageName(_ code: String) -> String {
        englishLocale.localizedString(forLanguageCode: code) ?? code
    }

    /// LLMs sometimes prepend "Sure, here's the translation:" or similar. Strip common
    /// preambles and trim quotes. Also drop everything before the first line break if
    /// the model emitted a label-then-newline pattern like "Russian:\nПеревод.".
    private static func cleanResponse(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a leading "X:" prefix (Qwen sometimes echoes the "Russian:" label from
        // the prompt onto its own output despite the "no labels" instruction).
        if let colon = s.firstIndex(of: ":"),
           s.distance(from: s.startIndex, to: colon) < 20 {
            let after = s.index(after: colon)
            let tail = s[after...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                s = tail
            }
        }

        // Strip common conversational preambles.
        let preambles = [
            "sure, here's the translation:",
            "sure, here is the translation:",
            "here's the translation:",
            "translation:"
        ]
        let lower = s.lowercased()
        for prefix in preambles where lower.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // Strip surrounding quotes if the model wrapped its output.
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }
}
#endif
