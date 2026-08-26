import Foundation

nonisolated protocol TranscriptSink: Sendable {
    func write(_ line: TranscriptLine) async throws
    func close() async
    func discard() async throws
}
