import Foundation

nonisolated struct SayAgainConfiguration: Sendable, Codable, Equatable {
    let endpointer: EndpointerConfig
    let transcription: TranscriptionConfig
    let translation: TranslationConfig
    let audio: AudioConfig
    let transcript: TranscriptConfig
    /// Languages the app knows about but doesn't yet support in this build (Apple STT/MT
    /// coverage gaps). Shown as "coming in the next version" in the UI.
    let planned: PlannedLanguages?

    static func loadFromBundle(name: String = "config", bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ConfigurationError.missing(name)
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ConfigurationError.malformed(underlying: error)
        }
    }
}

nonisolated struct EndpointerConfig: Sendable, Codable, Equatable {
    let minSpeechSeconds: Double
    let maxSpeechSeconds: Double
    let silenceHangoverSeconds: Double
    let preRollSeconds: Double
    let noiseFloorAlpha: Double
    let speechThresholdFactor: Double
}

nonisolated struct TranscriptionConfig: Sendable, Codable, Equatable {
    let spokenLanguages: [String]
    let hallucinationBlocklist: [String]
    let minConfidence: Double
    let maxNoSpeechProbability: Double
}

nonisolated struct TranslationConfig: Sendable, Codable, Equatable {
    let cacheLimit: Int
    let outputFilePrefix: String
    let outputFileExtension: String
    let availableTargets: [String]
}

nonisolated struct AudioConfig: Sendable, Codable, Equatable {
    let targetSampleRate: Double
    let channelCount: Int
}

nonisolated struct TranscriptConfig: Sendable, Codable, Equatable {
    let mainFilename: String
    let timestampFormat: String
    let truncateOnSessionStart: Bool
}

/// Languages we plan to add in a future release but don't ship yet in this SKU.
/// Surfaced in the UI as disabled rows with a "coming in the next version" badge so
/// users know the gap is intentional.
nonisolated struct PlannedLanguages: Sendable, Codable, Equatable {
    let recognition: [String]
    let translation: [String]
}
