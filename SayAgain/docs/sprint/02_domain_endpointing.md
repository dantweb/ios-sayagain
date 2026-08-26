# Layer: Endpointing

**Purpose.** Turn a continuous stream of `AudioBuffer`s into discrete utterances. Energy-based VAD with an adaptive noise floor. Direct port of the Python `Endpointer`, **including the bug fix landed 2026-08-25**.

**Why it stays in the domain even though the Apple stack segments natively.** The `StreamingTranscriber` port has two shapes: native-streaming (Apple, no endpointer needed) and batch (whisper.cpp, wrapped by `EndpointedTranscriber` — endpointer required). Keeping the endpointer in the domain is what lets a batch engine present the same streaming face. Sprint §"Two engine shapes, one port."

**MVP note.** The endpointer is implemented and tested, but the streaming path (Apple → `SpeechTranscriber`) does not route audio through it. It is exercised in tests only until a batch engine is added.

## Public type

```swift
public struct Endpointer: Sendable {
    public init(config: EndpointerConfig, clock: ClockProviding)
    public mutating func feed(_ buffer: AudioBuffer) -> [Utterance]
    public mutating func flush() -> Utterance?
}

public struct Utterance: Sendable {
    public let audio: AudioBuffer            // concatenated voiced audio (+ pre-roll)
    public let start: Date
    public let end: Date
}
```

Value semantics on purpose — the endpointer owns no I/O, no threading, no framework.

## Configuration

All read from `SayAgainConfiguration.endpointer`, never hardcoded.

| Field | Default | Meaning |
|---|---|---|
| `minSpeechSeconds` | 0.4 | An utterance shorter than this **measured on voiced audio** is discarded |
| `maxSpeechSeconds` | 12.0 | Force-split beyond this length; the split retains its audio |
| `silenceHangoverSeconds` | 0.6 | Trailing silence required to close an utterance |
| `preRollSeconds` | 0.25 | Audio kept *before* onset so leading consonants survive |
| `noiseFloorAlpha` | 0.05 | EMA smoothing of the noise floor when the frame is quiet |
| `speechThresholdFactor` | 3.0 | A frame is voiced if its RMS > `noiseFloor * factor` |

## The two defects, ported forward as regression tests

**Defect 1 (endpointing) — the minimum-speech gate.** The Python original measured the *padded* buffer (pre-roll + voiced audio + trailing silence). That total already exceeds any sane `minSpeechSeconds`, so *no blip is ever discarded*. Fix: measure **only the voiced samples**. This is Phase 2 test 2.4.

Defect 2 (hallucination blocklist) belongs to transcription — see [`03_domain_transcription.md`](03_domain_transcription.md).

## Behaviour

- Silence-in → nothing out. The utterance builder stays idle.
- Voiced-in → open an utterance if none is open; extend it if one is.
- Silence for `silenceHangoverSeconds` after voiced → close the utterance, emit if the **voiced portion** ≥ `minSpeechSeconds`, else discard.
- Length ≥ `maxSpeechSeconds` → force-emit the current utterance and immediately open a fresh one with pre-roll intact.
- `flush()` closes any open utterance (does *not* apply `minSpeechSeconds` — user stopped, we honour their last words). Returns `nil` if none was open.
- The noise floor is updated only from unvoiced frames, EMA-smoothed with `noiseFloorAlpha`. Voiced frames do not raise the floor. This is why sustained noise doesn't drift into "speech" (test 2.8).

## Phase 2 test list (all pure, all Foundation)

Sprint §"Phase 2 — the endpointer (pure)". Copied here for locality:

| # | Test | Proves |
|---|---|---|
| 2.1 | Silence alone produces no utterance | baseline |
| 2.2 | Tone between silences yields exactly one utterance | happy path |
| 2.3 | Two separated tones yield two utterances | segmentation |
| 2.4 | **A 0.15 s blip is discarded with `minSpeechSeconds` 0.4** | voiced-audio gate — fails if the padded buffer is measured |
| 2.5 | Speech beyond `maxSpeechSeconds` is force-split; the split keeps its audio | long-form does not stall |
| 2.6 | Pre-roll makes the utterance start *before* onset | no clipped leading consonant |
| 2.7 | `flush()` returns speech in progress; on idle it returns nothing | stopping loses nothing |
| 2.8 | Steady background noise never triggers | adaptive noise floor works |
| 2.9 | Lower sensitivity detects quiet speech that higher sensitivity misses | the dial does what the label says |

All test fixtures are synthetic `[Float]` buffers — sine tones, gaussian noise, and silence. No audio files bundled. Assertion values come from `SayAgainConfiguration`, never literals (sprint rule 5.4).

## MVP scope

- **In:** the port shape (`Endpointer` struct), config wiring, tests 2.1–2.9.
- **Deferred:** `EndpointedTranscriber` wrapper that composes an `Endpointer` with a batch `TranscriptionEngine` to satisfy `StreamingTranscriber` — added when a whisper adapter lands.

## Files (planned)

```
SayAgainKit/
└── Endpointing/
    ├── Endpointer.swift
    ├── EndpointerConfig.swift
    └── Utterance.swift
```
