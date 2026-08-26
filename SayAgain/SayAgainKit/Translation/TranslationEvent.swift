import Foundation

nonisolated enum TranslationEvent: Sendable {
    case translated(source: TranscriptLine, target: String, text: String)
    case skipped(source: TranscriptLine, target: String, reason: SkipReason)
    case failed(source: TranscriptLine, target: String, failure: TranslationFailure)
}

nonisolated enum SkipReason: Sendable, Equatable {
    case sameLanguage
    case noRoute
}

nonisolated enum TranslationFailure: Error, Sendable, Equatable {
    case backendFailed(String)
    case noRoute
    case cancelled
}
