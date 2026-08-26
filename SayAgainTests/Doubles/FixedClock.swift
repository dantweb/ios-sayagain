import Foundation
@testable import SayAgain

final class FixedClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }

    func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }
}
