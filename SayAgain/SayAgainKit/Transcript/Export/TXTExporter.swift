import Foundation

nonisolated struct TXTExporter: TranscriptExporter {
    let format: ExportFormat = .txt
    let timestampFormat: String

    init(timestampFormat: String = "HH:mm:ss") {
        self.timestampFormat = timestampFormat
    }

    func export(_ session: SessionSnapshot, shape: ExportShape) throws -> ExportedFile {
        let body: String
        switch shape {
        case .paragraphs:      body = paragraphsBody(session)
        case .stream:          body = streamBody(session)
        case .translationOnly: body = translationOnlyBody(session)
        }
        return ExportedFile(
            filename: filename(for: session),
            data: Data(body.utf8),
            uti: "public.plain-text"
        )
    }

    // MARK: - Shapes

    private func paragraphsBody(_ session: SessionSnapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = timestampFormat
        var lines: [String] = []
        for fl in session.lines {
            let ts = df.string(from: fl.line.time)
            lines.append("[\(ts)] [\(fl.line.language)] \(fl.line.text)")
            for target in fl.translations.keys.sorted() {
                if let text = fl.translations[target] {
                    lines.append("    [\(target)] \(text)")
                }
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func streamBody(_ session: SessionSnapshot) -> String {
        // Mirror the on-screen "Live stream" mode: just the transcribed text, sentences
        // separated by a blank line.
        let paragraphs = session.lines.map(\.line.text)
        return paragraphs.isEmpty ? "" : paragraphs.joined(separator: "\n\n") + "\n"
    }

    private func translationOnlyBody(_ session: SessionSnapshot) -> String {
        // Mirror the on-screen "Translation only" mode: only translations, skip lines that
        // never got translated.
        var lines: [String] = []
        for fl in session.lines where !fl.translations.isEmpty {
            for target in fl.translations.keys.sorted() {
                if let text = fl.translations[target] {
                    lines.append(text)
                }
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Filename

    private func filename(for session: SessionSnapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return "sayagain-\(df.string(from: session.startedAt)).txt"
    }
}
