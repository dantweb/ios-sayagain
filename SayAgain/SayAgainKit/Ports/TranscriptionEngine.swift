import Foundation

nonisolated protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult
}
