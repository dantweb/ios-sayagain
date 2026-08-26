# Layer: Adapters

**Purpose.** The only files in the project allowed to `import AVFoundation`, `import Speech`, `import Translation`. They implement the ports and translate framework types into the domain's `Foundation`-only value types. Sprint §"Package layout" — `Soundvibes/Adapters/`.

**Location.** `SayAgain/Adapters/` (inside the app target, not `SayAgainKit`).

## Adapter list (MVP)

| Port | Concrete adapter | Frameworks imported |
|---|---|---|
| `AudioCapturing` | `AVAudioCapturing` | `AVFoundation`, `AVFAudio` |
| `StreamingTranscriber` | `AppleSpeechTranscriber` | `Speech` (iOS 26 `SpeechTranscriber`) |
| `Translating` | `AppleTranslator` | `Translation` |
| `LanguageCatalog` | `AppleLanguageCatalog` | `Translation` |
| `TranscriptSink` | `FileTranscriptSink` | `Foundation` (lives in `SayAgainKit`, not here — file I/O is framework-free) |
| `ClockProviding` | `SystemClock` | `Foundation` (also in `SayAgainKit`) |

### `AVAudioCapturing`

- Configures `AVAudioSession` category `.playAndRecord`, mode `.measurement`, options `[.defaultToSpeaker, .allowBluetooth]`.
- Requests mic permission via `AVAudioApplication.requestRecordPermission` (iOS 17+).
- Installs a tap on the input node's bus 0 at the hardware format; converts to mono `Float32` at 16 kHz via `AVAudioConverter`.
- Emits `AudioBuffer` on the `onBuffer` callback. The callback is `@Sendable` — the tap thread hops onto a dedicated serial queue before invoking it.
- `stop()` removes the tap, deactivates the session with `.notifyOthersOnDeactivation`.

### `AppleSpeechTranscriber`

- Uses iOS 26 `SpeechTranscriber` (streaming API). See `DocumentationSearch` — this is new API, verify signatures at implementation time.
- Locale constraint = intersection of `configuration.spokenLanguages` and `SpeechTranscriber.supportedLocales`. If intersection is empty, fail with `TranscriberFailure.assetsUnavailable`.
- Emits `.volatile(text)` for `isFinal == false` transcriptions and `.final(TranscriptLine)` for `isFinal == true`, stamping `detectedLanguage` from the transcription result and `timestamp` from the injected clock.
- Handles `AssetInventory` — if a required language pack is missing, initiate the download; report progress via `.failed(TranscriberFailure.assetsUnavailable(...))` and retry on completion. Sprint test 6.3.

### `AppleTranslator`

- Wraps `TranslationSession` (from `Translation`). Sessions are per source-target pair; adapter maintains a pool keyed by `(from, to)`.
- `translate(text, from, to)` awaits `session.translate(text)`.
- Errors propagate as `Translating.Error` cases — the coordinator catches and emits `.failed` per-target.

### `AppleLanguageCatalog`

- `LanguageAvailability().supportedLanguages` filtered to those returning `.installed` or `.supported` from `availability.status(from:to:)` against every source in the configured spoken set.
- Localised display names via `Locale.current.localizedString(forLanguageCode:)`.
- Result cached until app foreground event (languages can install/uninstall in Settings).

## Info.plist (MVP additions)

| Key | Value | Reason |
|---|---|---|
| `NSMicrophoneUsageDescription` | "SayAgain transcribes what you say on this device. Audio never leaves your phone." | required for mic permission dialog |
| `UIFileSharingEnabled` | `YES` | expose Documents in Files.app |
| `LSSupportsOpeningDocumentsInPlace` | `YES` | show individual files, not just folder |

**Deliberately NOT added:** any URL scheme, `NSAppTransportSecurity`, background modes for audio (session use is foreground-only for MVP), CloudKit entitlements.

## Composition root

In `SayAgainApp.swift` (or a `Composition.swift`) — the *only* file that knows both an adapter and a coordinator by concrete name:

```swift
@MainActor
final class SessionEnvironment: ObservableObject {
    let capture: any AudioCapturing = AVAudioCapturing()
    let transcriber: any StreamingTranscriber = AppleSpeechTranscriber(clock: SystemClock())
    let translator: any Translating = AppleTranslator()
    let catalog: any LanguageCatalog = AppleLanguageCatalog()
    let config: SayAgainConfiguration = .loadFromBundle()
    // ... factories for coordinators
}
```

The UI receives this via `@EnvironmentObject`. No SwiftUI view ever names an adapter class.

## Phase 6 test list (integration, on-device)

All deferred for MVP — replaced by a manual verification checklist ([`07_ui.md`](07_ui.md#manual-verification-mvp)). Sprint tests 6.1–6.5 are kept in this doc as the on-device gates for when we do add integration tests:

| # | Test | Proves |
|---|---|---|
| 6.1 | `SpeechTranscriber` transcribes a bundled fixture clip per configured language | adapter wired |
| 6.2 | The adapter maps framework output onto `EngineResult`/events losslessly | seam honest |
| 6.3 | Missing language assets download via `AssetInventory`; run then succeeds | first launch works |
| 6.4 | With assets present and device in **airplane mode**, transcription and translation still work | offline claim, tested |
| 6.5 | Denied mic permission surfaces usable message, no crash | unhappy path |

## Files (planned)

```
SayAgain/
├── Adapters/
│   ├── AVAudioCapturing.swift
│   ├── AppleSpeechTranscriber.swift
│   ├── AppleTranslator.swift
│   └── AppleLanguageCatalog.swift
├── Composition/
│   └── SessionEnvironment.swift
└── Info.plist         (updated with three keys above)
```
