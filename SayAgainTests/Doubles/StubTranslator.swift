import Foundation
@testable import SayAgain

final class StubTranslator: Translating, @unchecked Sendable {
    struct Key: Hashable { let text: String; let from: String; let to: String }
    enum Failure: Error { case forced }

    private let lock = NSLock()
    private var mapping: [Key: String] = [:]
    private var throwingTargets: Set<String> = []
    private(set) var calls: [Key] = []

    func set(_ translated: String, for text: String, from source: String, to target: String) {
        lock.lock(); defer { lock.unlock() }
        mapping[Key(text: text, from: source, to: target)] = translated
    }

    func forceFailure(forTarget target: String) {
        lock.lock(); defer { lock.unlock() }
        throwingTargets.insert(target)
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        lock.lock()
        calls.append(Key(text: text, from: source, to: target))
        let shouldThrow = throwingTargets.contains(target)
        let mapped = mapping[Key(text: text, from: source, to: target)]
        lock.unlock()
        if shouldThrow { throw Failure.forced }
        return mapped ?? "[\(target)] \(text)"
    }
}
