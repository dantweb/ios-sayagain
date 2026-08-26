import Foundation

nonisolated enum ExportFormat: String, Sendable, CaseIterable, Hashable {
    case txt
    case csv
    // .docx is deferred (docs/sprint/05_domain_transcript_and_export.md)
}

nonisolated struct ExportedFile: Sendable, Hashable {
    let filename: String
    let data: Data
    let uti: String
}

nonisolated protocol TranscriptExporter: Sendable {
    var format: ExportFormat { get }
    func export(_ session: SessionSnapshot) throws -> ExportedFile
}
