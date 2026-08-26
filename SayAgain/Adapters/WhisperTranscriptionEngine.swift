import Foundation

/// Stub implementation of the batch `TranscriptionEngine` for languages Apple's
/// `SpeechTranscriber` doesn't cover (ru, pl, ro, hu, th).
///
/// **This is a stub** — until `WhisperKit` is added to the project via
/// **File → Add Package Dependencies…** in Xcode (see sprint doc 09), calling `transcribe`
/// throws a clear error so the UI can surface it to the user.
///
/// Slice 2 replaces the body of `transcribe(...)` with a `WhisperKit(model:)` call.
nonisolated final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {

    /// Model identifier — matches WhisperKit's naming when slice 2 lands.
    let modelName: String

    init(modelName: String = "openai_whisper-base") {
        self.modelName = modelName
    }

    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult {
        throw TranscriberFailure.assetsUnavailable(
            "WhisperKit not linked. Add https://github.com/argmaxinc/WhisperKit via " +
            "Xcode → File → Add Package Dependencies…, then rebuild. " +
            "See docs/sprint/09_non_native_engines.md."
        )
    }
}
