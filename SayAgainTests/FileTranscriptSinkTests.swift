import Foundation
import Testing
@testable import SayAgain

struct FileTranscriptSinkTests {

    // MARK: 5.1 — durability before close
    @Test func lineIsDurableImmediatelyAfterWriteBeforeClose() async throws {
        let url = Self.uniqueTempURL()
        let sink = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        try await sink.write(TranscriptLine(time: Date(timeIntervalSince1970: 1_700_000_000), language: "en", text: "hello"))

        // Read the file BEFORE close — durability means it must be there.
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("hello"))
        #expect(content.contains("[en]"))

        await sink.close()
    }

    // MARK: 5.2 — appending
    @Test func writingAppendsRatherThanTruncatingWhenConfigured() async throws {
        let url = Self.uniqueTempURL()
        let first = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        try await first.write(TranscriptLine(time: Date(timeIntervalSince1970: 1_700_000_000), language: "en", text: "one"))
        await first.close()

        let second = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: false))
        try await second.write(TranscriptLine(time: Date(timeIntervalSince1970: 1_700_000_060), language: "en", text: "two"))
        await second.close()

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("one"))
        #expect(content.contains("two"))
    }

    // MARK: truncate-on-open honours session policy
    @Test func truncatingOnOpenRemovesPreviousContent() async throws {
        let url = Self.uniqueTempURL()
        try Data("old\n".utf8).write(to: url)
        let sink = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        try await sink.write(TranscriptLine(time: Date(timeIntervalSince1970: 1_700_000_000), language: "en", text: "fresh"))
        await sink.close()

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.contains("old"))
        #expect(content.contains("fresh"))
    }

    // MARK: discard removes on-disk artefact
    @Test func discardDeletesTheFile() async throws {
        let url = Self.uniqueTempURL()
        let sink = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        try await sink.write(TranscriptLine(time: Date(), language: "en", text: "bye"))
        try await sink.discard()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: close is idempotent
    @Test func closeIsIdempotent() async throws {
        let url = Self.uniqueTempURL()
        let sink = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        await sink.close()
        await sink.close()
    }

    // MARK: writing after close throws
    @Test func writingAfterCloseThrows() async throws {
        let url = Self.uniqueTempURL()
        let sink = try FileTranscriptSink(url: url, config: SinkConfig(truncateOnOpen: true))
        await sink.close()
        await #expect(throws: SinkError.self) {
            try await sink.write(TranscriptLine(time: Date(), language: "en", text: "nope"))
        }
    }

    // MARK: - helpers

    static func uniqueTempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sayagain-\(UUID()).txt")
    }
}
