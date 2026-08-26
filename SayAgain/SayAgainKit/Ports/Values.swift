import Foundation

nonisolated struct AudioBuffer: Sendable, Hashable {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int
    let timestamp: Date

    var durationSeconds: Double {
        guard sampleRate > 0, channelCount > 0 else { return 0 }
        return Double(samples.count) / (sampleRate * Double(channelCount))
    }
}

nonisolated struct TranscriptLine: Sendable, Hashable, Codable, Identifiable {
    let id: UUID
    let time: Date
    let language: String
    let text: String
    let confidence: Double?

    init(id: UUID = UUID(), time: Date, language: String, text: String, confidence: Double? = nil) {
        self.id = id
        self.time = time
        self.language = language
        self.text = text
        self.confidence = confidence
    }
}

nonisolated struct TranslationLanguage: Sendable, Hashable, Identifiable {
    let code: String
    let displayName: String
    var id: String { code }
}

nonisolated enum MicrophonePermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case granted
    case restricted
}

nonisolated enum TranscriberFailure: Error, Sendable, Equatable {
    case engineFailed(String)
    case assetsUnavailable(String)
    case cancelled
    case notStarted
}

nonisolated enum TranscriptionEvent: Sendable {
    case volatile(String)
    case final(TranscriptLine)
    case failed(TranscriberFailure)
}

nonisolated struct EngineSegment: Sendable, Hashable {
    let text: String
    let confidence: Double
    let noSpeechProbability: Double
}

nonisolated struct EngineResult: Sendable, Hashable {
    let segments: [EngineSegment]
    let detectedLanguage: String?
    let languageProbability: Double?
}
