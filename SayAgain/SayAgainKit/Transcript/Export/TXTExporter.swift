import Foundation

nonisolated struct TXTExporter: TranscriptExporter {
    let format: ExportFormat = .txt
    let timestampFormat: String

    init(timestampFormat: String = "HH:mm:ss") {
        self.timestampFormat = timestampFormat
    }

    func export(_ session: SessionSnapshot) throws -> ExportedFile {
        let df = DateFormatter()
        df.dateFormat = timestampFormat

        var lines: [String] = []
        for fl in session.lines {
            let ts = df.string(from: fl.line.time)
            lines.append("[\(ts)] [\(fl.line.language)] \(fl.line.text)")
            // Translations indented under the original — matches the screen.
            let sortedTargets = fl.translations.keys.sorted()
            for target in sortedTargets {
                if let text = fl.translations[target] {
                    lines.append("    [\(target)] \(text)")
                }
            }
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        return ExportedFile(
            filename: filename(for: session),
            data: Data(body.utf8),
            uti: "public.plain-text"
        )
    }

    private func filename(for session: SessionSnapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return "sayagain-\(df.string(from: session.startedAt)).txt"
    }
}
