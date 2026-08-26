import Foundation

nonisolated struct TranscriptionPolicy: Sendable, Equatable {
    let allowedLanguages: [String]
    let hallucinationBlocklist: [String]
    let minConfidence: Double
    let maxNoSpeechProbability: Double

    init(config: TranscriptionConfig) {
        self.allowedLanguages = config.spokenLanguages
        self.hallucinationBlocklist = config.hallucinationBlocklist
        self.minConfidence = config.minConfidence
        self.maxNoSpeechProbability = config.maxNoSpeechProbability
    }

    init(allowedLanguages: [String], hallucinationBlocklist: [String], minConfidence: Double, maxNoSpeechProbability: Double) {
        self.allowedLanguages = allowedLanguages
        self.hallucinationBlocklist = hallucinationBlocklist
        self.minConfidence = minConfidence
        self.maxNoSpeechProbability = maxNoSpeechProbability
    }
}

nonisolated enum DisplayEvent: Sendable {
    case volatileUpdated(String)
    case finalised(TranscriptLine)
    case failure(TranscriberFailure)
}
