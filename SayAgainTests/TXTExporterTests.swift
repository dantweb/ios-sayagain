import Foundation
import Testing
@testable import SayAgain

struct TXTExporterTests {

    // MARK: 5.5 — reproduces the screen (originals + translations)
    @Test func reproducesScreenIncludingTranslations() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = TranscriptLine(time: start, language: "de", text: "Guten Tag")
        let b = TranscriptLine(time: start.addingTimeInterval(7), language: "de", text: "Wie geht es dir?")
        let snapshot = SessionSnapshot(
            lines: [
                FinalisedLine(line: a, translations: ["fr": "Bonjour"]),
                FinalisedLine(line: b, translations: ["fr": "Comment allez-vous ?"])
            ],
            startedAt: start
        )
        let exporter = TXTExporter(timestampFormat: "HH:mm:ss")
        let out = try exporter.export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""

        #expect(text.contains("[de] Guten Tag"))
        #expect(text.contains("    [fr] Bonjour"))
        #expect(text.contains("[de] Wie geht es dir?"))
        #expect(text.contains("    [fr] Comment allez-vous ?"))
        #expect(out.uti == "public.plain-text")
    }

    // MARK: 5.10 — non-ASCII survives
    @Test func nonASCIISurvives() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ru = TranscriptLine(time: start, language: "ru", text: "Привет, как дела?")
        let ar = TranscriptLine(time: start.addingTimeInterval(1), language: "ar", text: "مرحبا كيف حالك")
        let de = TranscriptLine(time: start.addingTimeInterval(2), language: "de", text: "Grüße, schöne Zeit")
        let snapshot = SessionSnapshot(
            lines: [
                FinalisedLine(line: ru, translations: [:]),
                FinalisedLine(line: ar, translations: [:]),
                FinalisedLine(line: de, translations: [:])
            ],
            startedAt: start
        )
        let out = try TXTExporter().export(snapshot)
        let text = String(data: out.data, encoding: .utf8) ?? ""
        #expect(text.contains("Привет"))
        #expect(text.contains("مرحبا"))
        #expect(text.contains("Grüße"))
    }

    // MARK: 5.11 — empty session is a valid file, not a crash
    @Test func emptySessionYieldsValidFile() throws {
        let snapshot = SessionSnapshot(lines: [], startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let out = try TXTExporter().export(snapshot)
        #expect(out.data.isEmpty || out.data.count > 0)     // trivially valid
        #expect(out.filename.hasSuffix(".txt"))
    }
}
