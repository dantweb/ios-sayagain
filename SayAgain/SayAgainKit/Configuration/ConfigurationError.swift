import Foundation

nonisolated enum ConfigurationError: Error, Equatable {
    case missing(String)
    case malformed(underlying: Error)

    static func == (lhs: ConfigurationError, rhs: ConfigurationError) -> Bool {
        switch (lhs, rhs) {
        case (.missing(let a), .missing(let b)): return a == b
        case (.malformed, .malformed): return true
        default: return false
        }
    }
}
