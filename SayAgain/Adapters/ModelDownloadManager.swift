#if SAYAGAINPLUS_TIER
import Foundation
import Observation
import Hub
import WhisperKit

/// Two logical model packs the Plus tier can download on demand.
///
/// Each pack is a single physical model that covers a *set* of languages, not one asset
/// per language:
/// - `.whisperSTT` — WhisperKit `openai_whisper-base` (~74 MB) — enables RU/PL/RO/HU/TH
///   transcription.
/// - `.llmMT` — MLX `Qwen2.5-1.5B-Instruct-4bit` (~1 GB) — enables RO/HU/TH translation.
///
/// Explicitly `nonisolated` because the project defaults new types to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Both the main-actor download manager and the
/// off-actor engines (`WhisperTranscriptionEngine`, `MLXLLMTranslator`) need to read
/// these paths, so opting out of that default is required.
nonisolated enum ModelPack: String, CaseIterable, Identifiable, Sendable {
    case whisperSTT
    case llmMT

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperSTT: return "Speech Recognition (Whisper)"
        case .llmMT:      return "Translator (LLM)"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperSTT: return "Adds Russian, Polish, Romanian, Hungarian, Thai transcription"
        case .llmMT:      return "Adds Romanian, Hungarian, Thai translation"
        }
    }

    var approxSizeLabel: String {
        switch self {
        case .whisperSTT: return "~244 MB"
        case .llmMT:      return "~1 GB"
        }
    }

    /// Directory the pack unpacks into. Deletion targets this.
    var modelDirectory: URL {
        switch self {
        case .whisperSTT:
            return Self.huggingFaceBase
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-small", isDirectory: true)
        case .llmMT:
            return Self.huggingFaceBase
                .appendingPathComponent("models/mlx-community/Qwen2.5-1.5B-Instruct-4bit", isDirectory: true)
        }
    }

    /// A file that only exists after a fully successful download. Interrupted downloads
    /// leave `.incomplete` siblings; the marker itself is atomically renamed into place last.
    var markerFile: URL {
        switch self {
        case .whisperSTT:
            return modelDirectory.appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin")
        case .llmMT:
            return modelDirectory.appendingPathComponent("config.json")
        }
    }

    var isInstalledOnDisk: Bool {
        FileManager.default.fileExists(atPath: markerFile.path)
    }

    /// Shared HuggingFace cache root. Placing WhisperKit and MLX under one base means
    /// "delete a pack" is one `rm -rf`.
    static var huggingFaceBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }
}

/// Thrown by the Whisper/LLM engines when the user has not yet downloaded the required
/// pack. `SessionViewModel` surfaces the message to the UI so it can prompt the user to
/// open Settings and install the pack.
struct EngineNotInstalledError: LocalizedError, Sendable {
    let pack: ModelPack
    var errorDescription: String? {
        "\(pack.displayName) not installed. Open Settings → Language Packs to download it."
    }
}

/// Manages downloading and deleting the Plus-tier model packs. State is `@Observable`
/// so the Settings UI can watch progress without any Combine plumbing.
@MainActor
@Observable
final class ModelDownloadManager {

    enum Status: Sendable, Equatable {
        case unknown
        case notInstalled
        case downloading(fraction: Double)
        case installed
        case failed(String)
    }

    private(set) var statuses: [ModelPack: Status] = [
        .whisperSTT: .unknown,
        .llmMT: .unknown
    ]

    private var tasks: [ModelPack: Task<Void, Never>] = [:]

    private let hub: HubApi

    init() {
        self.hub = HubApi(downloadBase: ModelPack.huggingFaceBase)
        refreshAll()
    }

    // MARK: - Inspection

    func refreshAll() {
        for pack in ModelPack.allCases {
            // Don't clobber a live download's `.downloading` status when re-probing.
            if case .downloading = statuses[pack] { continue }
            statuses[pack] = pack.isInstalledOnDisk ? .installed : .notInstalled
        }
    }

    // MARK: - Actions

    func download(_ pack: ModelPack) {
        guard tasks[pack] == nil else { return }
        statuses[pack] = .downloading(fraction: 0)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(pack)
                self.statuses[pack] = .installed
            } catch is CancellationError {
                self.statuses[pack] = pack.isInstalledOnDisk ? .installed : .notInstalled
            } catch {
                let message = (error as NSError).localizedDescription
                self.statuses[pack] = .failed(message)
                print("ModelDownloadManager: \(pack.rawValue) download failed — \(error)")
            }
            self.tasks[pack] = nil
        }
        tasks[pack] = task
    }

    func cancel(_ pack: ModelPack) {
        tasks[pack]?.cancel()
    }

    func delete(_ pack: ModelPack) {
        cancel(pack)
        try? FileManager.default.removeItem(at: pack.modelDirectory)
        statuses[pack] = .notInstalled
    }

    // MARK: - Downloaders

    private func performDownload(_ pack: ModelPack) async throws {
        switch pack {
        case .whisperSTT:
            // WhisperKit knows its own file layout (variant-scoped globs, .mlmodelc bundles),
            // so we let it drive the download rather than reconstructing the glob ourselves.
            _ = try await WhisperKit.download(
                variant: "openai_whisper-small",
                downloadBase: ModelPack.huggingFaceBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.applyProgress(pack: .whisperSTT, fraction: progress.fractionCompleted)
                    }
                }
            )
        case .llmMT:
            _ = try await hub.snapshot(
                from: Hub.Repo(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"),
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.applyProgress(pack: .llmMT, fraction: progress.fractionCompleted)
                    }
                }
            )
        }
    }

    /// Both HuggingFace Hub and WhisperKit occasionally fire a final `fractionCompleted = 1.0`
    /// callback *after* their `download(...)` closure has already returned. If we let those
    /// late updates through they clobber the `.installed` state we set on completion — which
    /// is exactly what left the Whisper row visually stuck at "100% + cancel" the first time
    /// through. Guarding on the current status keeps the transition monotonic.
    private func applyProgress(pack: ModelPack, fraction: Double) {
        guard case .downloading = statuses[pack] else { return }
        statuses[pack] = .downloading(fraction: fraction)
    }
}
#endif
