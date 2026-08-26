# Layer: Ports

**Purpose.** Every device or framework capability arrives as an injected protocol. The domain never mentions `AVFoundation`, `Speech` or `Translation`. This is what makes the domain tests run on a machine with no microphone, no speech model, and no network. Sprint §"Architecture — SOLID, applied", ports table.

**Package rule.** `SayAgainKit/**` imports `Foundation` only. Any other import is a defect. (Deferred lint: framework-lint. Not enforced by script in MVP — enforced by review.)

## Protocols

All in `SayAgainKit/Ports/`. Sendable-conforming where async boundaries cross actors.

### `AudioCapturing`
```swift
protocol AudioCapturing: Sendable {
    var permissionStatus: MicrophonePermissionStatus { get }
    func requestPermission() async -> MicrophonePermissionStatus
    func start(onBuffer: @Sendable @escaping (AudioBuffer) -> Void) throws
    func stop()
}
```
`AudioBuffer` is a value type: `samples: [Float]`, `sampleRate: Double`, `channelCount: Int`, `timestamp: Date`. Mono downmix happens in the adapter. Domain never sees `AVAudioPCMBuffer`.

### `StreamingTranscriber`
```swift
protocol StreamingTranscriber: Sendable {
    var events: AsyncStream<TranscriptionEvent> { get }
    func start(spokenLanguages: [String]) async throws
    func stop() async
}

enum TranscriptionEvent: Sendable {
    case volatile(String)                     // refines as the speaker talks
    case final(TranscriptLine)                // durable
    case failed(TranscriberFailure)           // engine-level, non-fatal to the session
}
```
This is the boundary the UI consumes. The Apple adapter emits `.volatile` and `.final` natively. A future batch adapter (e.g. `whisper.cpp`) wraps `EndpointedTranscriber` and emits `.final` only — same face.

### `TranscriptionEngine` (batch)
```swift
protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: AudioBuffer, language: String?) async throws -> EngineResult
}

struct EngineResult: Sendable {
    let segments: [EngineSegment]
    let detectedLanguage: String?
    let languageProbability: Double?
}
struct EngineSegment: Sendable { let text: String; let confidence: Double; let noSpeechProbability: Double }
```
Not used in MVP (Apple stack provides `StreamingTranscriber` directly). Port exists so the sprint's "two engine shapes, one port" stays honest.

### `Translating`
```swift
protocol Translating: Sendable {
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}
```
Language codes are BCP-47 primary tags (`"en"`, `"pt"`, `"zh-Hans"` allowed but not required in MVP). Pivot routing is *inside* the adapter if needed — the port doesn't leak it.

### `LanguageCatalog`
```swift
protocol LanguageCatalog: Sendable {
    func availableTargets() async -> [TranslationLanguage]
}

struct TranslationLanguage: Sendable, Hashable, Identifiable {
    let code: String            // "es"
    let displayName: String     // localised — "Spanish"
    var id: String { code }
}
```
Drives the `Translate to` dropdown. The UI never hardcodes a list.

### `TranscriptSink`
```swift
protocol TranscriptSink: Sendable {
    func write(_ line: TranscriptLine) async throws
    func close() async
    func discard() async throws          // deletes on-disk artefacts (used by Cancel / Clean)
}
```
`write` is **durable-on-return**: on success, the line is on disk and would survive an app crash. No user-space buffering. This is sprint test 5.1.

### `ClockProviding`
```swift
protocol ClockProviding: Sendable { func now() -> Date }
```
Injected so tests can pin timestamps.

## Value types

```swift
struct TranscriptLine: Sendable, Hashable, Codable {
    let id: UUID
    let time: Date
    let language: String        // detected or pinned
    let text: String
    let confidence: Double?
}

enum MicrophonePermissionStatus: Sendable { case notDetermined, denied, granted, restricted }
enum TranscriberFailure: Error, Sendable { case engineFailed(String), assetsUnavailable(String), cancelled }
```

## Phase 1 test list (adapted for folder-in-target)

Sprint tests 1.1–1.4 are about the *package boundary*. Since MVP keeps `SayAgainKit` as a folder inside the app target, the "structural" checks become **review checks + one test that scans the module for forbidden imports**:

| # | Test | Proves |
|---|---|---|
| 1.1 (adapted) | A test walks `SayAgainKit/**.swift` and asserts no line matches `import (AVFoundation\|Speech\|Translation\|Network\|Combine)` | Foundation-only surface, enforced by test rather than by SwiftPM manifest |
| 1.2 (deferred) | `offline-lint.sh` — `URLSession`, `Network`, `CFSocket` search across the whole app | Deferred; noted in `08_config_and_guards.md` |
| 1.4 | Every port has a test double in the test target | Injection is real, not aspirational |

## Test doubles (in `SayAgainKitTests/Doubles/`)

- `FakeAudioCapturing` — replays pre-recorded `[AudioBuffer]`
- `ScriptedStreamingTranscriber` — emits a scripted `[TranscriptionEvent]` sequence
- `ScriptedTranscriptionEngine` — returns a scripted `EngineResult` per call
- `StubTranslator` — configurable per-pair mapping; can throw for a target
- `StaticLanguageCatalog` — returns a fixed `[TranslationLanguage]`
- `InMemoryTranscriptSink` — records `write`s in order; `discard()` empties them
- `FixedClock` — returns a preset `Date`
