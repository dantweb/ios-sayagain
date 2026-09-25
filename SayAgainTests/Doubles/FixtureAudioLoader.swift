#if SAYAGAINPLUS_TIER
import Foundation
import WhisperKit
@testable import SayAgain

/// Loads bundled audio fixtures and hands them to callers as the 16 kHz mono Float32
/// buffers WhisperKit expects. Uses WhisperKit's own `AudioProcessor.loadAudioAsFloatArray`
/// so the decode path in tests matches the decode path production code would take.
enum FixtureAudioLoader {

    static let targetSampleRate: Double = 16_000

    /// Loads `<name>.wav` (falls back to `<name>.m4a`) from the test bundle's
    /// `Fixtures/audio/` folder and returns the samples as 16 kHz mono Float32 via
    /// WhisperKit's own audio loader.
    static func load(named name: String) throws -> AudioBuffer {
        let bundle = Bundle(for: TestBundleAnchor.self)
        let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures/audio")
            ?? bundle.url(forResource: name, withExtension: "wav")
            ?? bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Fixtures/audio")
            ?? bundle.url(forResource: name, withExtension: "m4a")
        guard let url else {
            throw FixtureError.missing("\(name).wav / .m4a not found in test bundle")
        }

        let raw = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        // AAC decoders occasionally emit Float32 samples outside the [-1, 1] range
        // (observed on these fixtures with peaks up to ~6.3). Whisper's mel-spectrogram
        // computation saturates on such input and the decoder falls back to repeating
        // a single token (e.g. "!!!!!!"). Peak-normalise to [-1, 1] before handing off.
        let peak = raw.map(abs).max() ?? 0
        let samples: [Float] = peak > 1.0 ? raw.map { $0 / peak } : raw
        return AudioBuffer(
            samples: samples,
            sampleRate: targetSampleRate,
            channelCount: 1,
            timestamp: Date()
        )
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let m): return m
            }
        }
    }
}

/// Empty class purely for `Bundle(for:)` to locate the test bundle.
private final class TestBundleAnchor {}
#endif
