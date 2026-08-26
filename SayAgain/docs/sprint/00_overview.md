# SayAgain — Sprint Overview

**Source sprint:** [`S149_ios_offline_voice_transcription_and_translation.md`](/Users/dantweb/dantweb/vbwd-sdk-2/docs/dev_log/20260826/sprints/S149_ios_offline_voice_transcription_and_translation.md)
**Status:** 🟡 MVP planning (2026-08-26)
**Naming:** the source sprint calls the artifacts `Soundvibes`/`SoundvibesKit` — that was the Python prototype. In this project they are **`SayAgain`** (app) and **`SayAgainKit`** (domain layer, folder for MVP; standalone Swift Package deferred).

## Product one-liner

One screen. Round green **Start**. Text appears while you speak. A **Translate to** dropdown that only lists what the device can honour. Everything runs on-device. No network code exists to leave through.

## Decisions locked in for MVP

| # | Decision | Rationale |
|---|---|---|
| 1 | `SayAgainKit` lives as a folder inside the app target, not a separate Swift Package | Folder-level SOLID discipline first; extract to a real package once the seams are proven. |
| 2 | iOS 26+ deployment target; `SpeechTranscriber` + `Translation` framework | Best battery, zero bundled models. The `TranscriptionEngine` port stays open so a `whisper.cpp` adapter is additive later. |
| 3 | Translation targets: **`[en, es, fr, de, it, pt, zh, ja, ko, ru, pl, ar]`** — Apple-safe subset | The dropdown is ultimately driven by `availableTargets()`, so this list is a *starting configuration*, not a promise. |
| 4 | Spoken-language recognition set = **same 12 languages** | Symmetry: every recognised language has at least one translation target. |
| 5 | Latest-session-only on disk (new session overwrites previous transcript files) | MVP does not ship history. |
| 6 | Four screen controls: **Start**, **Stop** (graceful drain), **Cancel** (hard discard — deletes on-disk files), **Clean** (wipes screen and on-disk files) | Explicit user answer 2026-08-26. |
| 7 | Transcripts live in the app's Documents container, **Files-app visible** (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`) | User can find the current transcript without exporting; still fully local. |
| 8 | Config lives in `Resources/config.json`, loaded into a `SayAgainConfiguration` `Codable` value type at startup | Satisfies sprint tests 5.3/5.4 from day one; no hardcoded tunables. |

## MVP scope (in)

- The four ports needed for the streaming path: `AudioCapturing`, `StreamingTranscriber`, `Translating`, `LanguageCatalog`, `TranscriptSink`, `ClockProviding`
- Energy-based endpointer with the **voiced-audio gate fix** (sprint §2, defect 1) — kept in the domain even though the Apple stack segments natively, because it's needed for any batch engine added later
- Transcription policy: language pinning, constrained detection, hallucination filter with the **normalisation fix** (sprint §2, defect 2), volatile→final in-place replacement
- Translation policy: per-target files (`translate.<LANG>.txt`), bounded cache, no-round-trip for same-language lines, forward-only mid-session switching, failure isolation
- Adapters: `AVAudioEngine` capture, `SpeechTranscriber` (native streaming), `Translation` framework, file-based transcript sink, `Date`-based clock
- Screen: Start (round green) → Stop / Cancel / Clean, live volatile→final text, `Translate to` picker built from `availableTargets()`, Export sheet with TXT + CSV, off-device warning for Mail/Notes destinations
- Config: `config.json` + `SayAgainConfiguration` struct
- Domain-level tests (Swift Testing framework) for endpointer, transcription policy, translation policy, TXT/CSV exporters

## Deferred (agreed 2026-08-26)

- **Splitting `SayAgainKit` into a standalone Swift Package** — folder discipline first, extract when stable
- **Phase 0 language-support probe** — see [`phase0_probe.md`](phase0_probe.md); the app will effectively probe live on first launch since the dropdown filters via `availableTargets()`
- **`whisper.cpp` batch engine + `EndpointedTranscriber` wrapper** — port shape kept clean, adapter additive
- **DOCX exporter** — TXT + CSV cover the MVP; OOXML by hand is a separate slice
- **XCUITest suite (Phase 7)** — replaced by a manual verification checklist for MVP
- **Guard scripts:** `offline-lint.sh`, framework-lint, port check, config check, durability check, language-coverage check, a11y check — listed in [`08_config_and_guards.md`](08_config_and_guards.md) so we do not forget; not implemented in MVP
- **Settings screen** — config values come from `config.json` only, no in-app editing
- **Multi-session history / iCloud / Files-app iCloud sync** — latest-session-only

## Layer index

| File | Layer | Depends on |
|---|---|---|
| [`01_ports.md`](01_ports.md) | Port protocols (Foundation-only surface) | — |
| [`02_domain_endpointing.md`](02_domain_endpointing.md) | Energy VAD, force-split, flush | Ports |
| [`03_domain_transcription.md`](03_domain_transcription.md) | Transcription policy | Ports, endpointing |
| [`04_domain_translation.md`](04_domain_translation.md) | Translation policy | Ports |
| [`05_domain_transcript_and_export.md`](05_domain_transcript_and_export.md) | Transcript sink, exporters | Ports |
| [`06_adapters.md`](06_adapters.md) | AVFoundation / Speech / Translation adapters | Ports, everything domain |
| [`07_ui.md`](07_ui.md) | SwiftUI screen | Adapters (via composition root) |
| [`08_config_and_guards.md`](08_config_and_guards.md) | Configuration + deferred guards inventory | — |
| [`phase0_probe.md`](phase0_probe.md) | Deferred: language-support measurement | — |

## Constraints inherited verbatim from the source sprint

1. **System audio cannot be captured on iOS. Permanently out of scope.** Not deferred.
2. **No VBWD SDK dependency, ever.** If accounts / licensing arrive, a VBWD plugin depends on `SayAgainKit`, never the reverse.
3. **The engine (domain) must import `Foundation` only.** No `AVFoundation`, no `Speech`, no `Translation`. Those live in `Adapters/`.
