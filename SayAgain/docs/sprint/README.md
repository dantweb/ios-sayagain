# SayAgain — Sprint Docs

Layered split of the S149 sprint spec, adapted for this project (`SayAgain` + `SayAgainKit`, MVP-first). The original sprint lives at [`vbwd-sdk-2/docs/dev_log/20260826/sprints/S149_ios_offline_voice_transcription_and_translation.md`](/Users/dantweb/dantweb/vbwd-sdk-2/docs/dev_log/20260826/sprints/S149_ios_offline_voice_transcription_and_translation.md).

## Read in this order

1. [`00_overview.md`](00_overview.md) — decisions locked in, MVP scope, deferred list, dependency map
2. [`01_ports.md`](01_ports.md) — the protocol boundary; every downstream layer targets these
3. [`02_domain_endpointing.md`](02_domain_endpointing.md) — energy VAD + the voiced-audio gate fix
4. [`03_domain_transcription.md`](03_domain_transcription.md) — policy, hallucination filter with normalisation fix, volatile→final
5. [`04_domain_translation.md`](04_domain_translation.md) — per-target files, cache, forward-only switching
6. [`05_domain_transcript_and_export.md`](05_domain_transcript_and_export.md) — durable sink, TXT + CSV exporters
7. [`06_adapters.md`](06_adapters.md) — AVAudioEngine, SpeechTranscriber (iOS 26), Translation framework
8. [`07_ui.md`](07_ui.md) — the one screen: Start / Stop / Cancel / Clean, target picker, Export
9. [`08_config_and_guards.md`](08_config_and_guards.md) — `config.json`, `SayAgainConfiguration`, deferred lints inventory
10. [`phase0_probe.md`](phase0_probe.md) — DEFERRED: language-support measurement + committed fixture

## SKU split — two Xcode targets, one `main` branch

**SayAgain** — default target, Apple-native only. `SpeechTranscriber` +
`Translation` framework. Apple-uncovered locales are surfaced in Settings as
"coming in the next version" but not selectable.

**SayAgainPlus** — sibling target activated by adding `SAYAGAINPLUS_TIER` to
its `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Adds WhisperKit STT for
`ru/pl/ro/hu/th` and (once bundled) OPUS-MT translation for `ro/hu/th`.

Files that compile only in the Plus tier are wrapped in
`#if SAYAGAINPLUS_TIER … #endif` guards. See `09_non_native_engines.md` for
the Xcode setup checklist and file list.

The `sayagainplus` branch (pre-split) preserves the earlier snapshot with the
Python conversion tooling for a future revisit — it is not the source of
truth any more.

## Dependency map (top of file depends on bottom)

```
UI (07)
 ├─→ Composition root (06)
 │    ├─→ Adapters (06)
 │    │    └─→ Ports (01)
 │    └─→ Coordinators (03, 04)
 │         ├─→ Ports (01)
 │         └─→ Endpointing (02)  — folded into a future EndpointedTranscriber only
 └─→ Transcript sink / exporters (05)
      └─→ Ports (01)

Configuration (08) is orthogonal — every layer reads it, no layer depends on it structurally.
```

## What each doc contains

- **Purpose** (1-2 sentences)
- **Public types / protocols** — Swift signatures
- **Behaviour** — the rules the layer enforces
- **Test list** — sprint's tests for that phase, marked MVP-in / deferred
- **MVP scope** — what ships in this pass, what defers
- **Files (planned)** — concrete filenames we'll create

## What none of them contain

- Implementation details of Apple framework calls — those go into the source files with `DocumentationSearch`-verified signatures at write-time
- Full test bodies — the tables state *what* each test proves; the test target files hold the assertions
