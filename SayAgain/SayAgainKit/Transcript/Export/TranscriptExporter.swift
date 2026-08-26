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

/// Shape of the transcript that should be exported — mirrors the on-screen display modes.
nonisolated enum ExportShape: String, Sendable, CaseIterable {
    /// Timestamped originals with translations underneath.
    case paragraphs
    /// Original text only, one line per finalised utterance.
    case stream
    /// Translated text only.
    case translationOnly
}

nonisolated protocol TranscriptExporter: Sendable {
    var format: ExportFormat { get }
    func export(_ session: SessionSnapshot, shape: ExportShape) throws -> ExportedFile
}

extension TranscriptExporter {
    /// Backwards-compatible default — used by existing tests that don't yet care about shape.
    func export(_ session: SessionSnapshot) throws -> ExportedFile {
        try export(session, shape: .paragraphs)
    }
}
