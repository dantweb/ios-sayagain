import Foundation
import Observation
import AVFoundation

/// Reads translated transcript lines aloud via `AVSpeechSynthesizer`. Publishes `isSpeaking`
/// and `currentLineID` so the UI can (a) toggle the play/stop button and (b) auto-scroll to
/// whichever line is being spoken.
@MainActor
@Observable
final class TranslationReader: NSObject {

    struct Line: Sendable {
        let id: UUID
        let text: String
        let languageCode: String
    }

    var isSpeaking: Bool = false
    var currentLineID: UUID? = nil

    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceToLine: [ObjectIdentifier: UUID] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Queue every line for speech. Starts from index 0. Existing speech is cancelled.
    func speak(lines: [Line]) {
        stop()
        guard !lines.isEmpty else { return }
        for line in lines {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = AVSpeechSynthesisVoice(language: line.languageCode)
            utteranceToLine[ObjectIdentifier(utterance)] = line.id
            synthesizer.speak(utterance)
        }
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        utteranceToLine.removeAll()
        currentLineID = nil
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TranslationReader: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.currentLineID = self?.utteranceToLine[key]
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.utteranceToLine.removeValue(forKey: key)
            if self.utteranceToLine.isEmpty {
                self.isSpeaking = false
                self.currentLineID = nil
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.utteranceToLine.removeValue(forKey: key)
        }
    }
}
