# Layer: Transcription Policy

**Purpose.** Turn `StreamingTranscriber` events into durable `TranscriptLine`s and volatile display strings, applying language constraints and hallucination filtering. Framework-free. Sprint §"Transcription policy" and §"The screen" (volatile→final behaviour).

## Public types

```swift
public actor TranscriptionCoordinator {
    public init(
        transcriber: any StreamingTranscriber,
        sink: any TranscriptSink,
        policy: TranscriptionPolicy,
        clock: any ClockProviding
    )

    public var stream: AsyncStream<DisplayEvent> { get }   // for the UI

    public func start(spokenLanguages: [String]) async throws
    public func stop() async          // graceful: flush volatile → final, close sink
    public func cancel() async        // hard: discard sink, drop volatile
}

public enum DisplayEvent: Sendable {
    case volatileUpdated(String)                 // replace the volatile line in the UI
    case finalised(TranscriptLine)               // append to the list, clear volatile
    case failure(TranscriberFailure)             // non-fatal; show a toast
}

public struct TranscriptionPolicy: Sendable {
    public let allowedLanguages: [String]
    public let hallucinationBlocklist: [String]
    public let minConfidence: Double
    public let maxNoSpeechProbability: Double
}
```

## Behaviour

**Language pinning vs auto-detect.**
- One allowed language → detection is skipped; that language is passed straight to `SpeechTranscriber` (adapter concern) and stamped on every line. Sprint test 3.2.
- Multiple → engine auto-detects. If the detected language is outside the allowed set, the coordinator asks the engine to redo the utterance with the best allowed candidate. Sprint tests 3.3–3.6.
- If no allowed candidate exists at all, keep the original result rather than fail (test 3.6).

**Quality gate.** Segments with `confidence < policy.minConfidence` or `noSpeechProbability > policy.maxNoSpeechProbability` are dropped before the line is assembled. Sprint test 3.7.

**Hallucination filter — with the normalisation fix (defect 2, sprint §2).**

The Python original stored blocklist entries verbatim (`"thank you."`) and compared against normalised speech (`"thank you"`). Whole-line matches worked; **mixed hallucination + real speech survived intact**. Fix: normalise **both sides** identically — lowercase, strip trailing punctuation, collapse whitespace, then substring-match.

```swift
func stripHallucinations(_ text: String, blocklist: [String]) -> String {
    let normalise: (String) -> String = { $0.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "[.!?,]+$", with: "", options: .regularExpression) }
    let bl = Set(blocklist.map(normalise))
    let words = text.split(separator: " ").map(String.init)
    // remove contiguous runs of blocked phrases; keep everything else
    // (see 3.8: real speech must survive when mixed with a stock invention)
}
```

Sprint tests 3.8 (mixed survives correctly) and 3.9 (pure hallucination yields no line).

**Volatile → final in place.** The UI holds one volatile string. Every `.volatile(text)` event *replaces* it. When `.final(line)` arrives, the volatile string clears and the line is appended to the finalised list. **No `.volatile` is ever written to the sink** — durability begins at `.final`. Sprint tests 3.11, 3.12.

**Stop is graceful; cancel is hard.**
- `stop()` finalises the current volatile text as a `TranscriptLine` (last words are not lost — test 3.14), drains, then `sink.close()`.
- `cancel()` drops the volatile line, calls `sink.discard()` (deletes on-disk artefacts), and does not finalise anything.

**Engine failures don't kill the session.** A `TranscriberFailure` on one utterance produces a `DisplayEvent.failure` and the coordinator continues. Sprint test 3.10.

## Phase 3 test list

| # | Test | Proves |
|---|---|---|
| 3.1 | A scripted result becomes a `TranscriptLine` with language and timestamp | shape |
| 3.2 | One configured language pins detection; engine called once | pinning skips detection |
| 3.3 | Several configured languages leave detection to the engine | auto-detect path |
| 3.4 | Detection outside the allowed set retries with best allowed language | constraint holds |
| 3.5 | Detection inside the allowed set is not retried | no wasted pass |
| 3.6 | No allowed candidate keeps original result rather than failing | degrade, don't crash |
| 3.7 | Low-confidence and probable-silence segments dropped | quality gate |
| 3.8 | **Hallucination mixed with real speech is removed; real speech survives** | normalisation fix |
| 3.9 | A line that is entirely hallucination yields no transcript line | silence stays silent |
| 3.10 | An engine that throws yields no line and does not end the session | one bad utterance ≠ lost meeting |
| 3.11 | `.volatile` followed by `.final` yields **one** line, not two | live text refines rather than duplicates |
| 3.12 | `.volatile` is **never** written to the sink | only finalised speech is durable |
| 3.13 | (deferred) `EndpointedTranscriber` wraps batch engine, emits `.final` only | batch engine presents streaming face |
| 3.14 | Stopping mid-phrase finalises volatile text rather than discarding | last words survive |

## MVP scope

- **In:** `TranscriptionCoordinator`, `TranscriptionPolicy`, hallucination filter with normalisation fix, all tests 3.1–3.12, 3.14.
- **Deferred:** 3.13 (`EndpointedTranscriber`), retry-with-language logic 3.4 requires a batch engine — MVP note: with `SpeechTranscriber` the constraint is enforced by locale set at start; runtime retry is not applicable. Test 3.4 is skipped until batch engine lands, with a comment.

## Files (planned)

```
SayAgainKit/
└── Transcription/
    ├── TranscriptionCoordinator.swift
    ├── TranscriptionPolicy.swift
    └── HallucinationFilter.swift
```
