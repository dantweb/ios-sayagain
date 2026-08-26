import Foundation

nonisolated struct FinalisedLine: Sendable, Hashable {
    let line: TranscriptLine
    let translations: [String: String]      // target language code → translated text
}

nonisolated struct SessionSnapshot: Sendable, Hashable {
    let lines: [FinalisedLine]
    let startedAt: Date
}
