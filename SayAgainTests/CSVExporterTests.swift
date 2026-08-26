import Foundation
import Testing
@testable import SayAgain

struct CSVExporterTests {

    // MARK: 5.6 — one row per line and declared columns
    @Test func headerAndRowPerLine() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SessionSnapshot(
            lines: [
                FinalisedLine(line: TranscriptLine(time: start, language: "en", text: "hi"), translations: [:]),
                FinalisedLine(line: TranscriptLine(time: start, language: "en", text: "there"), translations: [:])
            ],
            startedAt: start
        )
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)      // header + 2 rows
        #expect(lines[0] == "timestamp,source,language,text,translation_language,translation")
    }

    // MARK: 5.7 — escaping
    @Test func escapesQuotesCommasAndNewlines() throws {
        let line = TranscriptLine(
            time: Date(timeIntervalSince1970: 1_700_000_000),
            language: "en",
            text: "she said \"hi, world\"\nand left"
        )
        let snapshot = SessionSnapshot(lines: [FinalisedLine(line: line, translations: [:])], startedAt: Date())
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        #expect(text.contains("\"she said \"\"hi, world\"\"\nand left\""))
    }

    // MARK: 5.8 — untranslated session leaves translation columns empty, not absent
    @Test func untranslatedSessionHasEmptyTranslationColumns() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SessionSnapshot(
            lines: [FinalisedLine(line: TranscriptLine(time: start, language: "en", text: "solo"), translations: [:])],
            startedAt: start
        )
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        let bodyLines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(bodyLines.count == 2)
        // A row ending in ",," proves the two translation columns are present-but-empty.
        #expect(bodyLines[1].hasSuffix(",,"))
    }

    // MARK: multiple targets → one row per (line, target)
    @Test func multipleTargetsProduceOneRowEach() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SessionSnapshot(
            lines: [
                FinalisedLine(
                    line: TranscriptLine(time: start, language: "en", text: "hello"),
                    translations: ["es": "hola", "fr": "bonjour"]
                )
            ],
            startedAt: start
        )
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        let rows = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(rows.count == 3)          // header + 2 rows (one per target)
        #expect(rows.contains(where: { $0.contains(",es,hola") }))
        #expect(rows.contains(where: { $0.contains(",fr,bonjour") }))
    }

    // MARK: 5.10 — non-ASCII survives in CSV
    @Test func nonASCIISurvivesInCSV() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SessionSnapshot(
            lines: [
                FinalisedLine(line: TranscriptLine(time: start, language: "ru", text: "Привет"), translations: ["ar": "مرحبا"])
            ],
            startedAt: start
        )
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        #expect(text.contains("Привет"))
        #expect(text.contains("مرحبا"))
    }

    // MARK: 5.11 — empty session yields a valid file
    @Test func emptySessionYieldsHeaderOnly() throws {
        let snapshot = SessionSnapshot(lines: [], startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let out = try CSVExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        #expect(text.hasPrefix("timestamp,source,language,text,translation_language,translation"))
    }

    // MARK: 5.12 — a new exporter registers without editing existing ones
    @Test func newExporterRegistersWithoutEditingOthers() {
        var registry = ExporterRegistry.default
        #expect(registry.exporter(for: .txt) != nil)
        #expect(registry.exporter(for: .csv) != nil)

        struct FakeExporter: TranscriptExporter {
            let format: ExportFormat = .csv       // reuses the csv slot for the test
            func export(_ session: SessionSnapshot) throws -> ExportedFile {
                ExportedFile(filename: "fake.csv", data: Data("x".utf8), uti: "public.text")
            }
        }
        registry.register(FakeExporter())
        let file = try? registry.exporter(for: .csv)?.export(SessionSnapshot(lines: [], startedAt: Date()))
        #expect(file?.filename == "fake.csv")
    }
}
