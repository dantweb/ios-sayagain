import Foundation

nonisolated struct SinkConfig: Sendable, Equatable {
    let truncateOnOpen: Bool
    let timestampFormat: String
    let includesLanguageTag: Bool

    init(truncateOnOpen: Bool, timestampFormat: String = "HH:mm:ss", includesLanguageTag: Bool = true) {
        self.truncateOnOpen = truncateOnOpen
        self.timestampFormat = timestampFormat
        self.includesLanguageTag = includesLanguageTag
    }
}

nonisolated enum SinkError: Error, Equatable {
    case sinkClosed
    case fileHandleUnavailable
}
