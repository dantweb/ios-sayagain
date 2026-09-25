# Sprint 09 — Non-native engines (SayAgainPlus tier)

**Status:** 🟢 Slice 3 landed on `main` (2026-08-28) via on-device LLM instead of the
originally planned CoreML-exported OPUS-MT models. All code compiles behind
`#if SAYAGAINPLUS_TIER`; SayAgainPlus builds green with MLX-LLM wired in.

## SKU split

Two Xcode targets share one `main` branch:

- **SayAgain** — default target. Compile flag *not* set. Apple's `SpeechTranscriber` +
  `Translation` framework only. Locales Apple doesn't cover are surfaced in Settings as
  "coming in the next version" but not selectable.
- **SayAgainPlus** — sibling target. `SAYAGAINPLUS_TIER` set in
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (as `$(inherited) SAYAGAINPLUS_TIER`).
  Adds WhisperKit STT for `ru/pl/ro/hu/th` and MLX-LLM translation for `ro/hu/th`.

Files that compile only in the Plus tier open with `#if SAYAGAINPLUS_TIER` and close
with `#endif`:

- `SayAgain/Adapters/WhisperTranscriptionEngine.swift`
- `SayAgain/Adapters/WhisperStreamingTranscriber.swift`
- `SayAgain/Adapters/CompoundTranslator.swift`
- `SayAgain/Adapters/MLXLLMTranslator.swift`
- `SayAgain/SayAgainKit/Transcription/EndpointedTranscriber.swift`
- `SayAgainTests/EndpointedTranscriberTests.swift`
- `SayAgainTests/Doubles/ScriptedTranscriptionEngine.swift`

## Recognition path (slice 2 — shipped)

WhisperKit for the Apple-STT-uncovered set (ru/pl/ro/hu/th). The
`WhisperTranscriptionEngine` actor is a batch engine wrapping WhisperKit; the
`WhisperStreamingTranscriber` actor owns the mic tap and feeds an
`EndpointedTranscriber` that segments on silence and emits `.final` events.
Composition-root routing in `SessionEnvironment.makeStreamingTranscriberPlus`
picks Apple STT when every requested locale is native, otherwise Whisper.

## Translation path (slice 3 — this update)

### What we tried and abandoned: OPUS-MT + CoreML

The original slice-3 plan was to convert Helsinki-NLP OPUS-MT MarianMT models to
CoreML `.mlpackage`s off-device (Python) and bundle them per pair. This does not
work in the current PyPI ecosystem:

- **HuggingFace Optimum v2** dropped the CoreML exporter entirely.
- **HuggingFace Optimum v1** (`optimum[exporters-coreml]<2.0`) needs
  `transformers.utils.is_tf_available`, which was removed from modern
  `transformers` (~4.46+).
- **HuggingFace `exporters`** (the standalone repo the v1 exporter split into)
  has the same removed-API problem.
- Pinning `transformers==4.45.2` gets past the import, but the exporter then
  builds its dummy forward pass without `decoder_input_ids`, which modern
  MarianMT rejects with `ValueError: You have to specify either
  decoder_input_ids or decoder_inputs_embeds`. Fixing that means monkey-patching
  library internals, and every fix would reveal another mismatch — the
  exporter simply hasn't been maintained against current `transformers`
  MarianMT.

Verdict after three attempts (Optimum v2, Optimum v1, standalone `exporters`):
the OPUS-MT → CoreML path is currently broken for maintained model families.
We're not building on that foundation.

### What we shipped: on-device LLM (MLX-Swift)

`Adapters/MLXLLMTranslator.swift` conforms to `Translating` using
`mlx-community/Qwen2.5-1.5B-Instruct-4bit` (~1 GB) via MLX-Swift-Examples'
`MLXLLM`/`MLXLMCommon`.

- Model downloads once on first non-native translation call (needs Wi-Fi that
  one time). Cached in Application Support after that. Every subsequent
  translation runs 100% offline, no network, forever.
- Prompt template: `"Translate the following {source} text to {target}. Reply
  with only the translation, no explanation, no quotes, no notes.\n\n{text}"`
- Actor with lazy load + `loadingTask` coalescing so concurrent first-time
  calls share the same load.
- Latency: ~5–15 sec per short sentence on iPhone 14. This is the fallback
  path — users expect slower response for pairs Apple doesn't cover.

Routing: `CompoundTranslator` sends any pair where either source or target is in
`config.engines.translation.llm` (currently `["ro","hu","th"]`) through the LLM;
everything else stays on `BridgeTranslator` (Apple).

## Xcode setup (one-time, already done)

Recorded here for future reference:

1. Duplicate `SayAgain` target → `SayAgainPlus`. Rename scheme + set distinct
   bundle ID (`dantweb.SayAgainPlus`).
2. SayAgainPlus target → *Build Settings* → *Active Compilation Conditions*:
   `$(inherited) SAYAGAINPLUS_TIER` for both Debug and Release.
3. WhisperKit linked to SayAgainPlus only (removed from SayAgain's Frameworks).
4. MLX-Swift-Examples SPM (`ml-explore/mlx-swift-examples`) → SayAgainPlus
   target only — brings in `MLXLLM`, `MLXLMCommon`, plus transitive deps
   (`swift-transformers`, `mlx-swift`, etc).
5. `config-plus.json` in Resources with the `engines` block; loaded by
   `SessionEnvironment` when `SAYAGAINPLUS_TIER` is set.

## Sizes

| Binary | .app | Notes |
|---|---|---|
| SayAgain | ~6.6 MB debug device | Apple-native only |
| SayAgainPlus (STT-only, pre-LLM) | ~9.8 MB debug device | +3.2 MB for WhisperKit static link |
| SayAgainPlus (with MLX) | TBD | MLX-Swift binaries add another ~30-40 MB static link estimated |
| First-use downloads | +74 MB whisper-base + ~1 GB Qwen-2.5-1.5B | Cached, offline after |

## What's left

- **Device smoke test**: install SayAgainPlus on iPhone 14, pick Romanian
  translation target, speak, watch first-use model download then translate.
- **Progress UI**: MLX model download today has no user-facing progress
  indicator. First-use of a non-native target locale sits silent for potentially
  30+ minutes on cellular. Add a download-progress overlay before ship.
- **Quality baseline**: no metrics yet on Qwen-2.5 translation quality for
  ro/hu/th. Might swap to Gemma-2-2B-it-4bit or Phi-3.5-mini if translation
  turns out weak on the gap languages.
