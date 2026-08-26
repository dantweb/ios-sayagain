# Layer: Configuration & Guards

**Purpose.** One home for every tunable, loaded from a bundled JSON. Inventory of the sprint's guard scripts, all deferred for MVP, listed here so we don't quietly forget.

## `SayAgainConfiguration`

```swift
public struct SayAgainConfiguration: Sendable, Codable, Equatable {
    public let endpointer: EndpointerConfig
    public let transcription: TranscriptionConfig
    public let translation: TranslationConfig
    public let audio: AudioConfig
    public let transcript: TranscriptConfig
}

public struct EndpointerConfig: Sendable, Codable, Equatable {
    public let minSpeechSeconds: Double        // 0.4
    public let maxSpeechSeconds: Double        // 12.0
    public let silenceHangoverSeconds: Double  // 0.6
    public let preRollSeconds: Double          // 0.25
    public let noiseFloorAlpha: Double         // 0.05
    public let speechThresholdFactor: Double   // 3.0
}

public struct TranscriptionConfig: Sendable, Codable, Equatable {
    public let spokenLanguages: [String]                // ["en","es","fr","de","it","pt","zh","ja","ko","ru","pl","ar"]
    public let hallucinationBlocklist: [String]         // ["thank you.", "thanks for watching", ...]
    public let minConfidence: Double                    // 0.3
    public let maxNoSpeechProbability: Double           // 0.7
}

public struct TranslationConfig: Sendable, Codable, Equatable {
    public let cacheLimit: Int                          // 512
    public let outputFilePrefix: String                 // "translate"
    public let outputFileExtension: String              // "txt"
}

public struct AudioConfig: Sendable, Codable, Equatable {
    public let targetSampleRate: Double                 // 16000
    public let channelCount: Int                        // 1
}

public struct TranscriptConfig: Sendable, Codable, Equatable {
    public let mainFilename: String                     // "transcript.txt"
    public let timestampFormat: String                  // "HH:mm:ss"
    public let truncateOnSessionStart: Bool             // true (latest-session-only policy)
}
```

## Loading

```swift
public extension SayAgainConfiguration {
    static func loadFromBundle(name: String = "config", bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ConfigurationError.missing(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
```

The app's composition root calls this once at startup and hands the value down. Failure to load is a fatal launch error — the sprint's "one home for every tunable" rule requires the file to be authoritative, so degrading to Swift defaults would defeat the point.

## `Resources/config.json` (MVP)

```json
{
  "endpointer": {
    "minSpeechSeconds": 0.4,
    "maxSpeechSeconds": 12.0,
    "silenceHangoverSeconds": 0.6,
    "preRollSeconds": 0.25,
    "noiseFloorAlpha": 0.05,
    "speechThresholdFactor": 3.0
  },
  "transcription": {
    "spokenLanguages": ["en","es","fr","de","it","pt","zh","ja","ko","ru","pl","ar"],
    "hallucinationBlocklist": [
      "thank you.",
      "thanks for watching.",
      "please subscribe",
      "субтитры сделал",
      "다음 시간에"
    ],
    "minConfidence": 0.3,
    "maxNoSpeechProbability": 0.7
  },
  "translation": {
    "cacheLimit": 512,
    "outputFilePrefix": "translate",
    "outputFileExtension": "txt"
  },
  "audio": {
    "targetSampleRate": 16000,
    "channelCount": 1
  },
  "transcript": {
    "mainFilename": "transcript.txt",
    "timestampFormat": "HH:mm:ss",
    "truncateOnSessionStart": true
  }
}
```

## The rule that pays for itself: tests read config, never literals

Sprint test 5.4 — a direct lesson from the desktop tool 2026-08-25, where editing `config.yaml` broke 20 tests that had pinned the shipped values. In Swift, this looks like:

```swift
// BAD — will red on any config change
#expect(endpointer.minSpeechSeconds == 0.4)

// GOOD — asserts the wiring, not the value
#expect(endpointer.minSpeechSeconds == config.endpointer.minSpeechSeconds)
```

Applies to every test in every layer. Ship-blocker if a test hardcodes a tunable.

## Deferred guards (inventory)

All of these are sprint requirements. **None are implemented in MVP** — listed so we don't forget when we harden.

| Guard | What fails it | Deferred / planned |
|---|---|---|
| **offline lint** | `URLSession`, `Network`, `CFSocket`, host or URL literal anywhere in app or kit | Script `scripts/offline-lint.sh` running in CI. This is the most important guard — it turns the offline claim from a promise into a build-time refusal. |
| dependency lint | Package gains any dependency beyond `Foundation` | Trivial once the kit is a real Swift Package. Until then: review. |
| framework lint | `AVFoundation`, `Speech`, `Translation` referenced outside `Adapters/` | A test scanning `SayAgainKit/**.swift` — **doable now** (Phase 1.1 adapted). Consider adding to MVP if cheap. |
| port check | A view touches a capture or engine type directly | A test scanning `UI/**.swift` for adapter class names — cheap addition, same style as framework lint. |
| config check | A tunable hardcoded rather than read from configuration | Static analysis is hard; enforced by review. Test 5.4 is the runtime backstop. |
| durability check | Transcript line buffered rather than persisted on write | Sprint test 5.1 (in MVP) covers this. |
| language-coverage check | A configured target is absent from the Phase 0 fixture | Requires the fixture — deferred with Phase 0. In MVP the runtime filter via `availableTargets()` prevents the bad UX; the fixture will make it a build-time assertion. |
| a11y check | An interactive element ships without an identifier | Sprint test 7.17 — a small XCUITest launching the app and asserting every identifier. **Cheap enough to include in MVP** — see [`07_ui.md`](07_ui.md). |

Recommendation for follow-up slice after MVP: land offline-lint, framework-lint, port-check as three tiny bash scripts. Together they take a day and lock in most of the sprint's structural guarantees.

## Files (planned)

```
SayAgainKit/
└── Configuration/
    ├── SayAgainConfiguration.swift
    └── ConfigurationError.swift

SayAgain/
└── Resources/
    └── config.json
```
