#if SAYAGAINPLUS_TIER
import Foundation
import Testing
@testable import SayAgain

/// Integration tests that run bundled voice recordings through the real WhisperKit
/// pipeline and assert each language produces non-empty transcript with recognisable
/// characters. These tests download WhisperKit's model (~74 MB) on first run — expect
/// them to be slow.
///
/// One test per language so failures are attributed clearly (English passes but German
/// fails would show up as one red bar, not the whole suite red).
///
/// Serialized because WhisperKit's static model loader isn't safe for concurrent init
/// across instances — parallel runs produced `$$$$` garbage for all but one language.
@Suite(.serialized)
struct WhisperLanguageTranscriptionTests {

    // Long timeout tolerates the first-run model download.
    @Test(.timeLimit(.minutes(3)))
    func englishTranscribes() async throws {
        try await assertTranscribes(fixture: "en_GB", language: "en", minLetters: 5)
    }

    @Test(.timeLimit(.minutes(3)))
    func germanTranscribes() async throws {
        try await assertTranscribes(fixture: "de_DE", language: "de", minLetters: 5)
    }

    @Test(.timeLimit(.minutes(3)))
    func romanianTranscribes() async throws {
        try await assertTranscribes(fixture: "ro_RO", language: "ro", minLetters: 5)
    }

    // MARK: - Shared assertion

    /// Loads the audio fixture, transcribes it via `WhisperTranscriptionEngine` pinned
    /// to `language`, and asserts the returned text is non-empty and has at least
    /// `minLetters` letter characters (guards against Whisper returning e.g. "..." or
    /// a bracketed non-speech tag which is already filtered by `HallucinationFilter`
    /// but we want a stronger signal here).
    private func assertTranscribes(fixture: String, language: String, minLetters: Int) async throws {
        let audio = try FixtureAudioLoader.load(named: fixture)
        #expect(audio.samples.count > 0, "Fixture '\(fixture)' loaded zero samples")
        let rms = sqrt(audio.samples.map { $0 * $0 }.reduce(0, +) / Float(max(audio.samples.count, 1)))
        let peak = audio.samples.map(abs).max() ?? 0
        print("[WhisperLanguageTranscriptionTests] \(fixture) samples=\(audio.samples.count) rms=\(rms) peak=\(peak)")

        let engine = WhisperTranscriptionEngine()
        let result = try await engine.transcribe(audio, language: language)
        let text = result.segments.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[WhisperLanguageTranscriptionTests] \(fixture) (lang=\(language)) → \"\(text)\"")

        #expect(!text.isEmpty, "\(language): got empty transcription from \(fixture)")
        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        #expect(
            letterCount >= minLetters,
            "\(language): got only \(letterCount) letters (need ≥\(minLetters)): '\(text)'"
        )
    }
}
#endif
