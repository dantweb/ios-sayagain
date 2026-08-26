import Foundation
@testable import SayAgain

final class SinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: InMemoryTranscriptSink] = [:]

    func factory(for target: String) -> any TranscriptSink {
        lock.lock(); defer { lock.unlock() }
        if let existing = storage[target] { return existing }
        let fresh = InMemoryTranscriptSink()
        storage[target] = fresh
        return fresh
    }

    func sink(for target: String) -> InMemoryTranscriptSink? {
        lock.lock(); defer { lock.unlock() }
        return storage[target]
    }

    func allTargets() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(storage.keys)
    }
}
