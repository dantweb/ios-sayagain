import Foundation
import Translation

/// Bridges the domain's `Translating` port to SwiftUI's `.translationTask` modifier.
///
/// Rationale: `TranslationSession(installedSource:target:)` is fully headless but only works
/// when the language pack is already installed. Apple's canonical path — for both installed
/// languages and interactive downloads — is the `.translationTask(configuration:action:)` view
/// modifier, which delivers a `TranslationSession` bound to the view's lifecycle. This bridge
/// lets domain code call `translate(_:from:to:)` while a SwiftUI view drives the session.
@Observable
@MainActor
final class TranslationBridge {

    /// Bound to `.translationTask(configuration:)` in the view. When set (or invalidated) SwiftUI
    /// re-fires the task, which then drains pending requests via `run(session:)`.
    var currentConfig: TranslationSession.Configuration?

    private struct Pending {
        let text: String
        let from: String
        let to: String
        let continuation: CheckedContinuation<String, Error>
    }
    private var pending: [Pending] = []
    private var lastPair: PairKey?

    private struct PairKey: Equatable { let from: String; let to: String }

    // MARK: - Called by the domain via `BridgeTranslator`

    func enqueueAndAwait(text: String, from source: String, to target: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(Pending(text: text, from: source, to: target, continuation: continuation))
            let newPair = PairKey(from: source, to: target)
            if lastPair != newPair {
                // `.highFidelity` routes through Apple Intelligence when available (iOS 26+ on
                // supported devices) — noticeably better on hard pairs like es↔ru and de↔en.
                // Falls back to `.lowLatency` automatically when Apple Intelligence isn't there.
                currentConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target),
                    preferredStrategy: .highFidelity
                )
                lastPair = newPair
            } else if var config = currentConfig {
                config.invalidate()
                currentConfig = config
            }
        }
    }

    // MARK: - Called by SwiftUI view attached to `.translationTask`

    func run(with session: TranslationSession) async {
        guard let sourceCode = currentConfig?.source?.languageCode?.identifier,
              let targetCode = currentConfig?.target?.languageCode?.identifier else { return }

        let batch = pending.filter { $0.from == sourceCode && $0.to == targetCode }
        pending.removeAll { $0.from == sourceCode && $0.to == targetCode }

        for item in batch {
            do {
                let response = try await session.translate(item.text)
                item.continuation.resume(returning: response.targetText)
            } catch {
                print("TranslationBridge: \(sourceCode)→\(targetCode) failed for '\(item.text)' — \(error)")
                item.continuation.resume(throwing: error)
            }
        }
    }
}

/// Adapter conforming to `Translating`. Forwards to the bridge — safe to call from any actor.
nonisolated final class BridgeTranslator: Translating, @unchecked Sendable {
    private let bridge: TranslationBridge

    init(bridge: TranslationBridge) {
        self.bridge = bridge
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        try await bridge.enqueueAndAwait(text: text, from: source, to: target)
    }
}
