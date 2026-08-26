import Foundation
import Testing
@testable import SayAgain

struct ConfigurationTests {

    @Test func decodesFromLiteralJSON() throws {
        let json = """
        {
          "endpointer": {
            "minSpeechSeconds": 0.4, "maxSpeechSeconds": 12.0,
            "silenceHangoverSeconds": 0.6, "preRollSeconds": 0.25,
            "noiseFloorAlpha": 0.05, "speechThresholdFactor": 3.0
          },
          "transcription": {
            "spokenLanguages": ["en","es"],
            "hallucinationBlocklist": ["thank you."],
            "minConfidence": 0.3, "maxNoSpeechProbability": 0.7
          },
          "translation": {
            "cacheLimit": 512, "outputFilePrefix": "translate", "outputFileExtension": "txt",
            "availableTargets": ["en","es"]
          },
          "audio": { "targetSampleRate": 16000, "channelCount": 1 },
          "transcript": {
            "mainFilename": "transcript.txt",
            "timestampFormat": "HH:mm:ss",
            "truncateOnSessionStart": true
          }
        }
        """
        let config = try JSONDecoder().decode(SayAgainConfiguration.self, from: Data(json.utf8))
        #expect(config.endpointer.minSpeechSeconds == 0.4)
        #expect(config.transcription.spokenLanguages == ["en","es"])
        #expect(config.transcript.truncateOnSessionStart == true)
    }

    @Test func loadsFromAppBundle() throws {
        let config = try SayAgainConfiguration.loadFromBundle(bundle: .main)
        #expect(!config.transcription.spokenLanguages.isEmpty)
        #expect(config.endpointer.minSpeechSeconds > 0)
        #expect(config.endpointer.maxSpeechSeconds > config.endpointer.minSpeechSeconds)
    }

    @Test func missingResourceThrows() {
        let bundle = Bundle(for: BundleMarker.self)
        #expect(throws: ConfigurationError.self) {
            _ = try SayAgainConfiguration.loadFromBundle(name: "does-not-exist", bundle: bundle)
        }
    }
}

private final class BundleMarker {}
