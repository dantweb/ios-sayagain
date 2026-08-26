import Foundation

nonisolated struct CSVExporter: TranscriptExporter {
    let format: ExportFormat = .csv

    init() {}

    private static func isoFormatter() -> ISO8601DateFormatter {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df
    }

    func export(_ session: SessionSnapshot) throws -> ExportedFile {
        let iso = Self.isoFormatter()
        var rows: [String] = ["timestamp,source,language,text,translation_language,translation"]
        for fl in session.lines {
            let ts = iso.string(from: fl.line.time)
            let lang = fl.line.language
            let text = fl.line.text

            if fl.translations.isEmpty {
                rows.append(row([ts, "transcript", lang, text, "", ""]))
            } else {
                let sortedTargets = fl.translations.keys.sorted()
                for target in sortedTargets {
                    let translation = fl.translations[target] ?? ""
                    rows.append(row([ts, "transcript", lang, text, target, translation]))
                }
            }
        }
        let body = rows.joined(separator: "\n") + "\n"
        return ExportedFile(
            filename: filename(for: session),
            data: Data(body.utf8),
            uti: "public.comma-separated-values-text"
        )
    }

    private func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        if !needsQuoting { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    private func filename(for session: SessionSnapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return "sayagain-\(df.string(from: session.startedAt)).csv"
    }
}
