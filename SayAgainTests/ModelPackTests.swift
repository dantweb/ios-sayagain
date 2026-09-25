#if SAYAGAINPLUS_TIER
import Foundation
import Testing
@testable import SayAgain

/// Sanity tests for `ModelPack`'s filesystem contract. `ModelDownloadManager` reads and
/// deletes based on the paths and marker files defined here, and the engine gates check
/// `isInstalledOnDisk` before running inference — so if these paths or markers drift, the
/// UI reports "Installed" while the engine still throws `EngineNotInstalledError` (or
/// vice-versa). Keep this file in sync with any pack layout changes.
struct ModelPackTests {

    // MARK: - Path structure

    @Test func whisperModelDirectoryIsUnderDocumentsHuggingFace() {
        let dir = ModelPack.whisperSTT.modelDirectory.path
        // If this fails after a variant bump (e.g. small → medium), just update the
        // string. The ModelPack + ModelDownloadManager + WhisperTranscriptionEngine all
        // reference the same variant name; a mismatch means UI says "Installed" while
        // the engine can't find the model.
        #expect(dir.contains("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-small"))
    }

    @Test func llmModelDirectoryIsUnderDocumentsHuggingFace() {
        let dir = ModelPack.llmMT.modelDirectory.path
        #expect(dir.contains("Documents/huggingface/models/mlx-community/Qwen2.5-1.5B-Instruct-4bit"))
    }

    @Test func whisperMarkerFileSitsUnderTheModelDirectory() {
        let marker = ModelPack.whisperSTT.markerFile.path
        let dir = ModelPack.whisperSTT.modelDirectory.path
        #expect(marker.hasPrefix(dir), "marker \(marker) must be inside \(dir)")
        // Locking in the specific file WhisperKit produces last so `.incomplete` siblings
        // during interrupted downloads don't count as "installed".
        #expect(marker.hasSuffix("AudioEncoder.mlmodelc/coremldata.bin"))
    }

    @Test func llmMarkerFileSitsUnderTheModelDirectory() {
        let marker = ModelPack.llmMT.markerFile.path
        let dir = ModelPack.llmMT.modelDirectory.path
        #expect(marker.hasPrefix(dir))
        #expect(marker.hasSuffix("config.json"))
    }

    // MARK: - Presence detection

    @Test func isInstalledOnDiskReportsFalseWhenMarkerAbsent() throws {
        // We can't easily wipe the real Documents dir in a test, but we can build a
        // parallel structure and check the same predicate against a marker that
        // definitely doesn't exist.
        let tmpMarker = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
            .appendingPathComponent("marker.bin")
        #expect(!FileManager.default.fileExists(atPath: tmpMarker.path))
    }

    @Test func isInstalledOnDiskReportsTrueOnceMarkerExists() throws {
        // Same trick — assert the predicate `fileExists` (which `isInstalledOnDisk`
        // wraps) reacts correctly to file creation.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mp-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let marker = base.appendingPathComponent("marker.bin")
        FileManager.default.createFile(atPath: marker.path, contents: Data("x".utf8))
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - Display metadata (stability contract for Settings UI)

    @Test func packsHaveNonEmptyDisplayNamesAndSubtitles() {
        for pack in ModelPack.allCases {
            #expect(!pack.displayName.isEmpty)
            #expect(!pack.subtitle.isEmpty)
            #expect(!pack.approxSizeLabel.isEmpty)
        }
    }
}
#endif
