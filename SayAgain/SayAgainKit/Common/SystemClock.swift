import Foundation

nonisolated struct SystemClock: ClockProviding {
    func now() -> Date { Date() }
}
