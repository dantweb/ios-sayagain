import Foundation

nonisolated protocol StreamingTranscriber: Sendable {
    var events: AsyncStream<TranscriptionEvent> { get }
    func start(spokenLanguages: [String]) async throws
    func stop() async
}
