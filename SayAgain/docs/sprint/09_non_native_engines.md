# Sprint 09 — Non-native STT and translation engines

**Status:** 🟡 IN PROGRESS (2026-08-26). Slice 1 (this doc + `EndpointedTranscriber` + stubs + routing) lands with this sprint; slice 2 (WhisperKit wiring) after user adds SPM; slice 3 (NLLB translation) later.

**Motivation.** Apple's `SpeechTranscriber` and `Translation` framework don't cover Romanian, Hungarian, Thai, and (for translation) many pairs. To honour the sprint's principle "the app promises only what the device can do" while covering these languages, we add non-native engines behind the *existing* ports.

## Coverage today (iOS 26, iPhone 14)

| Lang | Apple STT | Apple MT |
|---|---|---|
| en, es, fr, de, it, pt, zh, ja, ko, ar | ✅ | ✅ |
| pl | ❌ | ✅ |
| ru | ❌ | ✅ |
| ro | ❌ | ❌ |
| hu | ❌ | ❌ |
| th | ❌ | ❌ |

**Gap:** STT for ru, pl, ro, hu, th; MT for ro, hu, th (plus tough pairs like es↔ru whose native quality is weak).

## Architecture — reuse the ports, add adapters

The sprint's port design already accommodates this. Nothing in `SayAgainKit/` changes.

### Recognition path

```
Session start
    │
    ▼
SessionEnvironment.makeTranscriber(for locale)
    │
    ├── locale ∈ Apple-supported ────► AppleSpeechTranscriber (native)
    │
    └── locale ∈ {ru, pl, ro, hu, th} ─► EndpointedTranscriber
                                            │
                                            ▼
                                       WhisperTranscriptionEngine
```

`WhisperTranscriptionEngine` implements the existing `TranscriptionEngine` (batch) port. `EndpointedTranscriber` implements the existing `StreamingTranscriber` port by composing an `Endpointer` (already implemented, tested, currently unused in the Apple path) with a batch engine.

### Translation path

```
TranslationCoordinator.translate(...)
    │
    ▼
CompoundTranslator
    │
    ├── pair supported by Apple ────► BridgeTranslator (SwiftUI translationTask)
    │
    └── pair ∉ Apple ──────────────► NLLBTranslator (offline CoreML)
```

Both conform to `Translating`. `CompoundTranslator` routes per-pair.

## Slice plan

### Slice 1 — plumbing (this sprint)

1. `SayAgainKit/Transcription/EndpointedTranscriber.swift` — wraps `TranscriptionEngine` + `Endpointer` to satisfy `StreamingTranscriber`. Emits `.final` only (batch engines don't stream volatile).
2. `Adapters/WhisperTranscriptionEngine.swift` — stub that throws `TranscriberFailure.engineFailed("WhisperKit not linked")` until slice 2 wires the real engine. Compiles without WhisperKit.
3. `Adapters/NLLBTranslator.swift` — stub `Translating` that throws until slice 3 provides the model.
4. `Composition/SessionEnvironment.swift` — per-locale routing driven by config.
5. `Resources/config.json` — new `engines` block:
   ```json
   "engines": {
     "recognition": {
       "native": ["en","es","fr","de","it","pt","zh","ja","ko","ar"],
       "whisper": ["ru","pl","ro","hu","th"]
     },
     "translation": {
       "native": ["en","es","fr","de","it","pt","zh","ja","ko","ar","ru","pl"],
       "nllb":   ["ro","hu","th"]
     }
   }
   ```
6. Tests for `EndpointedTranscriber` — silence, tone, force-split, flush.

At this slice's end, the app still runs identically for Apple-supported languages. Non-native languages fail loudly with "engine not wired yet" — visible to the user as `⚠︎ WhisperKit not linked`.

### Slice 2 — WhisperKit STT (after user adds SPM dep)

1. In Xcode: **File → Add Package Dependencies…** → `https://github.com/argmaxinc/WhisperKit`, version rule "Up to Next Major", target `SayAgain`.
2. Bundle model `openai_whisper-base` (~74 MB) via WhisperKit's model manager (`WhisperKit(model: "openai_whisper-base")` — downloads on first use, then cached).
3. Replace `WhisperTranscriptionEngine` stub with real impl:
   - `init(languageCode:)`
   - `transcribe(_ audio: AudioBuffer, language:) async throws -> EngineResult`
   - Internally: `WhisperKit.transcribe(audioArray: [Float])` → map segments to `EngineSegment`s + set `detectedLanguage`.
4. Wire into `SessionEnvironment` per-locale routing.
5. Add integration test that runs a bundled short audio clip through the engine on-device.

**Expected quality:** whisper `base` handles the five non-native languages well (WER ~15-25% depending on accent/noise). `small` (~244 MB) is noticeably better if we want to ship a bigger app.

**Latency:** batch-per-utterance. `EndpointedTranscriber` cuts on silence (≥ `silenceHangoverSeconds` = 0.3 s configured), then whisper `base` transcribes an utterance in ~200-800 ms on iPhone 14. Users see `.final` events per utterance; no volatile.

### Slice 3 — NLLB translation for RO/HU/TH pairs

1. Off-device (Python): convert `facebook/nllb-200-distilled-600M` to CoreML via `coremltools`. Weight quantization to int8 → ~300 MB `.mlpackage`.
2. Bundle `.mlpackage` in `SayAgain/Resources/` (or lazy-download on first non-native pair to spare the app-store binary size).
3. `NLLBTranslator` uses `MLModel` + a tokenizer (SentencePiece via `SwiftSentencePiece` or bundled BPE tables).
4. Register with `CompoundTranslator`; `TranslationCoordinator` calls it transparently for non-Apple pairs.

**Alternative if NLLB proves impractical:** `TranslationSession(installedSource:target:)` pivot through English for pairs where Apple has both hops. Covers es↔pl (both via en). Doesn't help ro/hu/th.

**Deferred until slice 3 lands:** the config's `translation.nllb` route falls back to a stub that reports "translation model not available", so users see clear feedback rather than a silent failure.

## Ports — no changes

- `StreamingTranscriber` — same shape. Native adapter emits `.volatile` + `.final`; endpointed adapter emits `.final` only.
- `TranscriptionEngine` (batch) — was scaffolded from day one. Now finally has a real conformer.
- `Translating` — same shape. `CompoundTranslator` composes two conformers per pair.
- `LanguageCatalog` — new implementation that unions native + whisper support for the "recognition supported" badge; and native + nllb for the "translation supported" badge.

## Tests

New unit tests (Swift Testing, still in `SayAgainTests/`):

| Suite | Tests |
|---|---|
| `EndpointedTranscriberTests` | silence-produces-nothing · tone-produces-one-final · two-tones-produce-two-finals · force-split-mid-utterance · stop-flushes-in-progress · engine-error-yields-failure-event |
| `CompoundTranslatorTests` | routes native-pair-to-native · routes non-native-pair-to-fallback · unknown-target-throws |

Deferred (require the real engines):

- On-device integration: WhisperKit transcribes a bundled RU / PL / RO / HU / TH clip
- On-device integration: NLLB translates a fixed source string in each new pair, output matches a stored reference (fuzzy character-similarity threshold, not exact match)

## Storage & permissions impact

| Slice | Added binary | Added download on first use | New permission |
|---|---|---|---|
| 1 | +5 KB (Swift code) | none | none |
| 2 | +10 MB (WhisperKit + dependencies) | +74 MB (whisper `base` model, one-time) | none |
| 3 | +variable | +300 MB (NLLB quantized) | none |

Nothing in the plan requires network at runtime after model download completes. The offline claim holds.

## Guards (deferred — noted for follow-up)

- **Engine-routing check**: static analysis that recognition/translation routes in `config.json` cover every language the user can pick in Settings.
- **Model-integrity check**: at first launch after install, hash-verify the whisper and NLLB models before use; refuse to run against a corrupt cache.

## Files (slice 1 concrete list)

```
SayAgain/docs/sprint/
└── 09_non_native_engines.md                (this file)

SayAgainKit/
└── Transcription/
    └── EndpointedTranscriber.swift          NEW — batch → streaming

Adapters/
├── WhisperTranscriptionEngine.swift         NEW — stub
├── NLLBTranslator.swift                     NEW — stub
└── CompoundTranslator.swift                 NEW — per-pair routing

Composition/
└── SessionEnvironment.swift                 UPDATED — engine routing

Resources/
└── config.json                              UPDATED — engines block

SayAgainKit/Configuration/
└── SayAgainConfiguration.swift              UPDATED — EngineConfig type

SayAgainTests/
└── EndpointedTranscriberTests.swift         NEW
```
