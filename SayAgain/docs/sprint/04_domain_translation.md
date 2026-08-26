# Layer: Translation Policy

**Purpose.** For each finalised `TranscriptLine`, emit a translation into each active target language, write it to a per-target file, cache repeats, and never let one target's failure poison another. Sprint §"Translation policy".

## Public types

```swift
public actor TranslationCoordinator {
    public init(
        translator: any Translating,
        catalog: any LanguageCatalog,
        sinkFactory: @Sendable (_ target: String) -> any TranscriptSink,
        cacheLimit: Int,
        clock: any ClockProviding
    )

    public var stream: AsyncStream<TranslationEvent> { get }   // for the UI

    public func setTargets(_ targets: [String]) async         // forward-only; see below
    public func handleFinal(_ line: TranscriptLine) async
    public func close() async
    public func discardAll() async throws                     // Cancel / Clean
}

public enum TranslationEvent: Sendable {
    case translated(source: TranscriptLine, target: String, text: String)
    case skipped(source: TranscriptLine, target: String, reason: SkipReason)
    case failed(source: TranscriptLine, target: String, error: Error)
}

public enum SkipReason: Sendable { case sameLanguage, noRoute }
```

## Behaviour

**One output file per target.** Naming per config: `translate.<LANG>.txt` (matches desktop tool). Every finalised line reaches every currently-active target. The mixed-language main transcript remains distinct and untouched. Sprint tests 4.1, 4.2, 4.9.

**No round-trip when source == target.** Line already in target language is copied through, not translated. Sprint test 4.3.

**Bounded cache.** `(source_text, source_lang, target_lang) → translated_text`, bounded at `cacheLimit`. LRU eviction. Sprint tests 4.4, 4.5.

**Failure isolation.**
- One target throws → emit `TranslationEvent.failed`, skip that line for that target, continue with other targets. Sprint tests 4.6, 4.7.
- The failure never propagates out to `handleFinal`'s caller.

**Pivot routing.** With Apple's `Translation` framework, pair availability is handled internally by the framework — no code work required. **The pivot routing (source → en → target when no direct pair exists) applies only when a bundled model backs `Translating`.** In MVP it's a note in the port doc, not code. Sprint test 4.8 is deferred with the whisper adapter.

**Volatile is never translated.** `TranscriptionCoordinator` filters to `.final` before this actor sees it. Sprint test 4.10.

**Forward-only mid-session switching.**
- `setTargets(["es"])` at time T → all lines finalised **at or after T** are translated to `es`.
- Lines already displayed / already in `translate.<lang>.txt` for previous targets are **not** re-translated. Sprint tests 4.11, 4.12.
- Setting `[]` (via UI's `None`) turns translation off from the next line forward.
- Setting the same target again is idempotent — the file already exists, we append.

**Available-targets constraint.** The UI must not offer a target that `catalog.availableTargets()` didn't return. The coordinator additionally *asserts* on `handleFinal` that the requested target is available; an unavailable target degrades to `skipped(.noRoute)`. Sprint test 4.13.

## Phase 4 test list

| # | Test | Proves |
|---|---|---|
| 4.1 | One output per target, named per config prefix | file contract |
| 4.2 | Every line reaches every target | promise |
| 4.3 | Line already in target language is copied, not translated | no round-trip |
| 4.4 | Repeated text translated once | bounded cache |
| 4.5 | Cache eviction re-translates beyond the limit | bounded means bounded |
| 4.6 | Failing target loses one line; others unaffected | isolation |
| 4.7 | Failing target never propagates error | Liskov |
| 4.8 | (deferred) Pair with no direct route translates via pivot | Argos lesson, ported when whisper lands |
| 4.9 | Mixed transcript keeps original text untranslated | two outputs distinct |
| 4.10 | Volatile text never reaches the translator | no wasted work |
| 4.11 | **Changing target mid-session translates subsequent lines only** | forward-only |
| 4.12 | Selecting `None` mid-session stops translating from next line | off switch works forward |
| 4.13 | `availableTargets()` drives the offered list; unavailable never offered | the app promises only what the device can do |

## MVP scope

- **In:** `TranslationCoordinator`, per-target file writing, LRU cache, failure isolation, forward-only switching, same-language skip, all tests 4.1–4.7, 4.9–4.13.
- **Deferred:** pivot routing + test 4.8, until a bundled-model translator lands.

## Files (planned)

```
SayAgainKit/
└── Translation/
    ├── TranslationCoordinator.swift
    ├── TranslationCache.swift          // LRU
    └── TranslationEvents.swift
```
