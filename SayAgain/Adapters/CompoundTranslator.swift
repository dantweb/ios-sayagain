#if SAYAGAINPLUS_TIER
import Foundation

/// Routes each `translate(_:from:to:)` call to one of the underlying translators according
/// to a per-target policy: the native (Apple) translator by default, the offline LLM
/// translator for language codes the native side doesn't cover.
///
/// The two underlying conformers stay unaware of each other. Failure in one doesn't cascade
/// to the other — the caller just gets the routing-decision's error.
nonisolated final class CompoundTranslator: Translating, @unchecked Sendable {

    /// Set of language codes (target- OR source-side) that force the LLM path. Everything
    /// else goes through `native`.
    let llmLanguages: Set<String>
    private let native: any Translating
    private let llm: any Translating

    init(native: any Translating, llm: any Translating, llmLanguages: Set<String>) {
        self.native = native
        self.llm = llm
        self.llmLanguages = llmLanguages
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        // Route by target first — the user's picked language is the discriminator. If either
        // source or target is only offered by the LLM, use the LLM.
        if llmLanguages.contains(target) || llmLanguages.contains(source) {
            return try await llm.translate(text, from: source, to: target)
        }
        return try await native.translate(text, from: source, to: target)
    }

    /// Forward warm-up to both sides. Apple's native side is cheap to warm; the LLM side
    /// is where the real ~1 GB load happens. Running both in parallel via a task group
    /// so a slow side doesn't block the other.
    func warmUp() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [native] in await native.warmUp() }
            group.addTask { [llm] in await llm.warmUp() }
            await group.waitForAll()
        }
    }
}
#endif
