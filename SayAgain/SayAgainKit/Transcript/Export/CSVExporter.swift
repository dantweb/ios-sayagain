import Foundation

nonisolated struct CSVExporter: TranscriptExporter {
    let format: ExportFormat = .csv

    init() {}

    private static func isoFormatter() -> ISO8601DateFormatter {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df
    }

    func export(_ session: SessionSnapshot, shape: ExportShape) throws -> ExportedFile {
        let iso = Self.isoFormatter()
        let body: String
        switch shape {
        case .paragraphs:      body = paragraphsBody(session, iso: iso)
        case .stream:          body = streamBody(session, iso: iso)
        case .translationOnly: body = translationOnlyBody(session, iso: iso)
        }
        return ExportedFile(
            filename: filename(for: session),
            data: Data(body.utf8),
            uti: "public.comma-separated-values-text"
        )
    }

    // MARK: - Shapes

    private func paragraphsBody(_ session: SessionSnapshot, iso: ISO8601DateFormatter) -> String {
        var rows: [String] = ["timestamp,source,language,text,translation_language,translation"]
        for fl in session.lines {
            let ts = iso.string(from: fl.line.time)
            if fl.translations.isEmpty {
                rows.append(row([ts, "transcript", fl.line.language, fl.line.text, "", ""]))
            } else {
                for target in fl.translations.keys.sorted() {
                    let translation = fl.translations[target] ?? ""
                    rows.append(row([ts, "transcript", fl.line.language, fl.line.text, target, translation]))
                }
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func streamBody(_ session: SessionSnapshot, iso: ISO8601DateFormatter) -> String {
        // Live-stream shape: original text only, no translation columns.
        var rows: [String] = ["timestamp,language,text"]
        for fl in session.lines {
            rows.append(row([iso.string(from: fl.line.time), fl.line.language, fl.line.text]))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func translationOnlyBody(_ session: SessionSnapshot, iso: ISO8601DateFormatter) -> String {
        // Translation-only shape: one row per translation, source omitted.
        var rows: [String] = ["timestamp,translation_language,translation"]
        for fl in session.lines where !fl.translations.isEmpty {
            let ts = iso.string(from: fl.line.time)
            for target in fl.translations.keys.sorted() {
                let text = fl.translations[target] ?? ""
                rows.append(row([ts, target, text]))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - CSV helpers

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
