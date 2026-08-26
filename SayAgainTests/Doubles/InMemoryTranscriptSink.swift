import Foundation
@testable import SayAgain

final class InMemoryTranscriptSink: TranscriptSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [TranscriptLine] = []
    private(set) var closeCallCount: Int = 0
    private(set) var discardCallCount: Int = 0

    var lines: [TranscriptLine] {
        lock.lock(); defer { lock.unlock() }
        return _lines
    }

    func write(_ line: TranscriptLine) async throws {
        lock.lock(); defer { lock.unlock() }
        _lines.append(line)
    }

    func close() async {
        lock.lock(); defer { lock.unlock() }
        closeCallCount += 1
    }

    func discard() async throws {
        lock.lock(); defer { lock.unlock() }
        _lines.removeAll()
        discardCallCount += 1
    }
}
