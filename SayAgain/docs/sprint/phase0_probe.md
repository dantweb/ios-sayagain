# Phase 0 — Language-Support Probe

**Status:** 🔴 **DEFERRED for MVP** (agreed 2026-08-26)
**Kept as its own file because it's evidence-gathering, not a code layer.**

## Why the sprint made this Phase 0

Apple's `Translation` framework covers roughly 20 languages. The Python prototype targeted `[ru, pl, hu, fi, bg, ar]` — Hungarian, Finnish, Bulgarian are near-certainly not supported by Apple. The sprint refuses to guess: **the fixture picks the engine.**

## Why we're deferring it for MVP

Two reasons:

1. **The UX already handles the answer either way.** The `Translate to` dropdown is populated from `LanguageCatalog.availableTargets()` at runtime. An unsupported language simply doesn't appear — the app never promises what it can't deliver (sprint tests 4.13, 7.5).
2. **The MVP language selection is the Apple-safe subset** (`[en, es, fr, de, it, pt, zh, ja, ko, ru, pl, ar]`) — all near-certain to be supported. The languages that would fail the probe (`hu, fi, bg`) are not in the MVP config.

So MVP effectively probes live on every launch. What we lose: a *committed fixture* that the build can assert against.

## What Phase 0 must produce (when we un-defer)

1. A throwaway probe target (or a debug-only view in the app) that:
   - Prints `SpeechTranscriber.supportedLocales` on the target OS.
   - Calls `LanguageAvailability().supportedLanguages`.
   - Calls `availability.status(from:to:)` for every `(spoken, target)` pair in `config.json`.
2. A committed fixture file at `SayAgainKitTests/Fixtures/language_support.json` with the exact matrix.
3. A test that reads the fixture and asserts:
   - every `transcription.spokenLanguages` entry appears in `SpeechTranscriber.supportedLocales`,
   - every configured target either has a direct path from every spoken language or has an English pivot,
   - a target reported unsupported fails the assertion loudly.

## Phase 0 test list (verbatim from sprint)

| # | Test | Proves |
|---|---|---|
| 0.1 | Probe prints a non-empty `SpeechTranscriber.supportedLocales` on device | on-device speech exists on the target OS |
| 0.2 | Every configured spoken language appears in the supported set | we can transcribe what we claim to |
| 0.3 | Every target is checked against `LanguageAvailability` and recorded in a committed fixture | engine decision is evidence, not assumption |
| 0.4 | A target reported unsupported fails the fixture assertion loudly | the constraint cannot be forgotten later |

## When to un-defer

- Before shipping to real users.
- If we add any language outside the Apple-safe subset (in particular: Hungarian, Finnish, Bulgarian, Turkish, Ukrainian) — those *need* the fixture because they force the "bundle a model" question the sprint's Open Question #2 asks.

## Related decisions in `00_overview.md`

- Decision 3 (translation target list) — currently the Apple-safe subset, which is why we can defer this phase.
- Decision 4 (spoken languages = translation targets) — same reason.
