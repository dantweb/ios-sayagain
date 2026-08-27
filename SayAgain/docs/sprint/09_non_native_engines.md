# Sprint 09 — Non-native engines (SayAgainPlus tier)

**Status:** 🟡 Code landed on `main` behind `#if SAYAGAINPLUS_TIER` (2026-08-27).
Awaiting Xcode target duplication to activate the flag.

## SKU split

Two Xcode targets share one `main` branch:

- **SayAgain** — default target. Compile flag *not* set. Uses only Apple's
  `SpeechTranscriber` and `Translation` framework. Ships to users who don't
  need offline `ru/pl/ro/hu/th` coverage.
- **SayAgainPlus** — sibling target. `SAYAGAINPLUS_TIER` set in the target's
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Adds WhisperKit STT for
  `ru/pl/ro/hu/th` and (once shipped) OPUS-MT translation for `ro/hu/th`.

Files that only compile in the Plus tier open with `#if SAYAGAINPLUS_TIER` and
close with `#endif`:

- `SayAgain/Adapters/WhisperTranscriptionEngine.swift`
- `SayAgain/Adapters/WhisperStreamingTranscriber.swift`
- `SayAgain/Adapters/CompoundTranslator.swift`
- `SayAgain/Adapters/NLLBTranslator.swift`
- `SayAgain/SayAgainKit/Transcription/EndpointedTranscriber.swift`
- `SayAgainTests/EndpointedTranscriberTests.swift`
- `SayAgainTests/Doubles/ScriptedTranscriptionEngine.swift`

`SessionEnvironment.swift` has one entry point that branches on the flag to
compose either the native or the compound wiring.

## Xcode setup (one time)

1. **Duplicate the target.** In Xcode's Project navigator, click the project,
   then in the TARGETS panel right-click `SayAgain` → **Duplicate**.
2. **Rename** the duplicate to `SayAgainPlus`. Xcode also creates a scheme —
   rename that too (Product → Scheme → Manage Schemes…).
3. **Bundle identifier.** In SayAgainPlus's *General* tab set a distinct
   bundle ID, e.g. `dantweb.SayAgainPlus`.
4. **Compile flag.** SayAgainPlus target → *Build Settings* → find
   **Active Compilation Conditions** (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`).
   Add `SAYAGAINPLUS_TIER` to both Debug and Release columns.
5. **File membership** (optional cleanup — SayAgain compiles the Plus files
   as no-ops today, so this step just shrinks the base binary): select each
   Plus-only source in the file navigator, and in *File Inspector* →
   *Target Membership* uncheck `SayAgain`, keep `SayAgainPlus` checked.
6. **WhisperKit dependency.** SayAgain target → *General* → *Frameworks,
   Libraries, and Embedded Content*: remove `WhisperKit`. SayAgainPlus →
   same panel → add `WhisperKit` from the existing `argmax-oss-swift`
   package reference.
7. **Config file for Plus.** Duplicate `SayAgain/Resources/config.json` as
   `config-plus.json` at the same location. In the copy: widen
   `transcription.spokenLanguages` to include `ru, pl, ro, hu, th`; widen
   `translation.availableTargets`; drop the `planned` block; add an
   `engines` block per the shape below. Set `config-plus.json` target
   membership to SayAgainPlus only.

### Plus `engines` block shape

```json
"engines": {
  "recognition": {
    "native":  ["en","es","fr","de","it","pt","zh","ja","ko","ar"],
    "whisper": ["ru","pl","ro","hu","th"]
  },
  "translation": {
    "native": ["en","es","fr","de","it","pt","zh","ja","ko","ar","ru","pl"],
    "nllb":   ["ro","hu","th"]
  }
}
```

## Verify

- SayAgain scheme: build + run all tests → 59 pass, 5 EndpointedTranscriberTests
  not-run (they're behind the flag).
- SayAgainPlus scheme: build + run all tests → all 64 pass.

## Deferred

The offline OPUS-MT translation model itself is still not bundled — the
`NLLBTranslator` stub throws a "not available" message. The Python
conversion tooling that was tried and rolled back lives on branch
`sayagainplus` (pre-split); revisit when the HuggingFace Optimum CoreML
exporter (or a manual `coremltools` path) is stable.
