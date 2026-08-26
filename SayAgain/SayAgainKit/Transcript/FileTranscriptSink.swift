import Foundation

actor FileTranscriptSink: TranscriptSink {
    private let url: URL
    private let config: SinkConfig
    private let formatter: DateFormatter
    private var handle: FileHandle?
    private var isClosed: Bool = false

    init(url: URL, config: SinkConfig) throws {
        self.url = url
        self.config = config
        self.formatter = DateFormatter()
        self.formatter.dateFormat = config.timestampFormat
        try Self.prepareFile(at: url, truncate: config.truncateOnOpen)
        self.handle = try FileHandle(forWritingTo: url)
        try self.handle?.seekToEnd()
    }

    private static func prepareFile(at url: URL, truncate: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if truncate, fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
    }

    func write(_ line: TranscriptLine) async throws {
        guard !isClosed else { throw SinkError.sinkClosed }
        guard let handle = handle else { throw SinkError.fileHandleUnavailable }

        let formatted = formatLine(line)
        try handle.write(contentsOf: Data(formatted.utf8))
        try handle.synchronize()   // fsync — durable-on-return (Phase 5.1)
    }

    func close() async {
        guard !isClosed else { return }
        try? handle?.close()
        handle = nil
        isClosed = true
    }

    func discard() async throws {
        try? handle?.close()
        handle = nil
        isClosed = true
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private func formatLine(_ line: TranscriptLine) -> String {
        let ts = formatter.string(from: line.time)
        if config.includesLanguageTag {
            return "[\(ts)] [\(line.language)] \(line.text)\n"
        } else {
            return "[\(ts)] \(line.text)\n"
        }
    }
}
