import Foundation

nonisolated struct ExporterRegistry: Sendable {
    private var exporters: [ExportFormat: any TranscriptExporter]

    init(_ exporters: [any TranscriptExporter] = []) {
        var map: [ExportFormat: any TranscriptExporter] = [:]
        for e in exporters { map[e.format] = e }
        self.exporters = map
    }

    static let `default`: ExporterRegistry = ExporterRegistry([
        TXTExporter(timestampFormat: "HH:mm:ss"),
        CSVExporter()
    ])

    var registered: [ExportFormat] { Array(exporters.keys) }

    func exporter(for format: ExportFormat) -> (any TranscriptExporter)? {
        exporters[format]
    }

    mutating func register(_ exporter: any TranscriptExporter) {
        exporters[exporter.format] = exporter
    }
}
