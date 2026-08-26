import Foundation

nonisolated struct SayAgainConfiguration: Sendable, Codable, Equatable {
    let endpointer: EndpointerConfig
    let transcription: TranscriptionConfig
    let translation: TranslationConfig
    let audio: AudioConfig
    let transcript: TranscriptConfig
    /// Per-language engine routing (Whisper for STT, NLLB for MT). Optional so existing
    /// configs load without the block; defaults keep everything on the native path.
    let engines: EnginesConfig?

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

/// Which engine handles which language.
///
/// - `recognition.native` — locales handled by Apple's `SpeechTranscriber`
/// - `recognition.whisper` — locales handled by the WhisperKit-based batch engine
/// - `translation.native` — pairs handled by Apple's `Translation` framework (any-to-any)
/// - `translation.nllb` — languages that force the pair through NLLB even if the other side is native
nonisolated struct EnginesConfig: Sendable, Codable, Equatable {
    let recognition: RecognitionRouting
    let translation: TranslationRouting
}

nonisolated struct RecognitionRouting: Sendable, Codable, Equatable {
    let native: [String]
    let whisper: [String]
}

nonisolated struct TranslationRouting: Sendable, Codable, Equatable {
    let native: [String]
    let nllb: [String]
}
