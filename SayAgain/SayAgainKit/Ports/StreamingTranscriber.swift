import Foundation

nonisolated protocol StreamingTranscriber: Sendable {
    var events: AsyncStream<TranscriptionEvent> { get }
    func start(spokenLanguages: [String]) async throws
    func stop() async
    /// Optional pre-warm: adapters that own an expensive model (WhisperKit) implement
    /// this to load weights into memory before the user's first utterance arrives, so
    /// time-to-first-transcript isn't dominated by cold-start. Default is a no-op.
    func warmUp() async
}

extension StreamingTranscriber {
    func warmUp() async {}
}
