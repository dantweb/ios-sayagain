import Foundation

nonisolated protocol ClockProviding: Sendable {
    func now() -> Date
}
