# Layer: Transcript sink & Export

**Purpose.** Persist finalised lines durably; format sessions for export in TXT/CSV. Both are pure Foundation. Sprint §"Export" and §"Phase 5".

## Transcript sink

```swift
public struct FileTranscriptSink: TranscriptSink {
    public init(fileURL: URL, config: SinkConfig)
    public func write(_ line: TranscriptLine) async throws     // fsync-durable
    public func close() async                                   // idempotent
    public func discard() async throws                          // delete the file
}
```

### Durability contract

**On successful return of `write`, the line is on disk.** Not buffered in userspace, not queued to a background writer. If the app is killed the next instant, the line survives. This is sprint test 5.1 — the single most important behaviour of the sink.

Implementation: open a `FileHandle` in append mode, write UTF-8 bytes, `synchronize()` (POSIX `fsync`), return. One `FileHandle` per sink instance; serialised via actor or `NSLock`.

### Latest-session-only policy

Session start truncates the target file(s). `TranscriptionCoordinator.start()` builds a sink with `SinkConfig.truncateOnOpen = true`. `Cancel` and `Clean` call `discard()`, which unlinks the file.

Files:
- `transcript.txt` — the main mixed-language stream
- `translate.<LANG>.txt` — one per active target

All live in `Documents/`. See [`06_adapters.md`](06_adapters.md) for the concrete URL and Files-app visibility.

### Line format

```
[HH:mm:ss] [lang] text
```
Example: `[14:32:07] [de] Guten Tag, wie geht es dir?`

Timestamps use the injected `ClockProviding`; the formatter is UTC-safe but display-time is local — the sprint's screen mockup uses local time.

## Export

```swift
public protocol TranscriptExporter: Sendable {
    var format: ExportFormat { get }
    func export(_ session: SessionSnapshot) throws -> ExportedFile
}

public enum ExportFormat: Sendable, CaseIterable { case txt, csv /* .docx deferred */ }
public struct ExportedFile: Sendable { let filename: String; let data: Data; let uti: String }

public struct SessionSnapshot: Sendable {
    public let lines: [TranscriptLine]
    public let translations: [String: [TranscriptLine]]   // target lang → parallel lines
    public let startedAt: Date
}

public enum ExporterRegistry {
    public static func exporter(for format: ExportFormat) -> any TranscriptExporter
    // OCP: register(_:) exists but MVP ships txt+csv only
}
```

### TXT

Reproduces the screen:
```
Guten Tag, wie geht es dir?
Bonjour, comment allez-vous ?      // present only if this target was active for that line
ich wollte noch kurz sagen…
```
Sprint test 5.5 — export matches session.

### CSV

Columns: `timestamp,source,language,text,translation_language,translation`

- One row per finalised line per active-at-the-time target. If no target was active, the two translation columns are empty (not absent). Sprint test 5.8.
- Escaping: quote the field with `"`, double any embedded `"`. Commas and newlines are legal inside a quoted field. Sprint test 5.7.
- Non-ASCII (Cyrillic, Arabic, umlauts) survives verbatim as UTF-8. Sprint test 5.10.

### DOCX — deferred

OOXML by hand is a package (ZIP) with `[Content_Types].xml`, `word/document.xml`, `word/_rels/document.xml.rels`, etc. Correct output is fiddly and not in MVP scope. `ExporterRegistry` is designed so `.docx` is an additive `register(DOCXExporter())` call later. Sprint test 5.9 deferred; test 5.12 (new exporter registers without editing existing ones) is still met — the registry pattern is in from day one.

## Phase 5 test list (adapted for MVP)

| # | Test | MVP status |
|---|---|---|
| 5.1 | A line is durable immediately after `write`, before `close` | **In** — the crucial one |
| 5.2 | Writing appends rather than truncating | **In** — asserted with `SinkConfig.truncateOnOpen = false` |
| 5.3 | Defaults are read from bundled configuration, not hardcoded | **In** — see [`08_config_and_guards.md`](08_config_and_guards.md) |
| 5.4 | Every test asserts against configuration rather than pinned literals | **In** — hard rule |
| 5.5 | TXT export reproduces what the screen showed, translations included | **In** |
| 5.6 | CSV one row per finalised line, declared columns | **In** |
| 5.7 | CSV escapes quotes, commas, newlines | **In** |
| 5.8 | Untranslated session leaves translation columns empty, not absent | **In** |
| 5.9 | DOCX is a valid OOXML package | **Deferred** |
| 5.10 | Non-ASCII survives every format | **In** for TXT+CSV |
| 5.11 | Exporting an empty session yields a valid file, not a crash | **In** |
| 5.12 | A new exporter registers without editing existing ones | **In** — registry pattern present |

## Files (planned)

```
SayAgainKit/
└── Transcript/
    ├── FileTranscriptSink.swift
    ├── TranscriptLine.swift        (also referenced by Ports/)
    └── Export/
        ├── TranscriptExporter.swift
        ├── ExporterRegistry.swift
        ├── TXTExporter.swift
        └── CSVExporter.swift
```
