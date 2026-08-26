import Foundation
@testable import SayAgain

final class ScriptedStreamingTranscriber: StreamingTranscriber, @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    let events: AsyncStream<TranscriptionEvent>
    private(set) var startCalls: [[String]] = []
    private(set) var stopCallCount: Int = 0

    init() {
        var cont: AsyncStream<TranscriptionEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func start(spokenLanguages: [String]) async throws {
        lock.lock()
        startCalls.append(spokenLanguages)
        lock.unlock()
    }

    func stop() async {
        lock.lock()
        stopCallCount += 1
        lock.unlock()
        continuation.finish()
    }

    func emit(_ event: TranscriptionEvent) {
        continuation.yield(event)
    }
}
