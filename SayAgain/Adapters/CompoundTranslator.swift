import Foundation

/// Routes each `translate(_:from:to:)` call to one of the underlying translators according
/// to a per-target policy: the native (Apple) translator by default, the NLLB translator for
/// language codes the native side doesn't cover.
///
/// The two underlying conformers stay unaware of each other. Failure in one doesn't cascade
/// to the other — the caller just gets the routing-decision's error.
nonisolated final class CompoundTranslator: Translating, @unchecked Sendable {

    /// Set of language codes (target-side) that should be routed to NLLB. Everything else
    /// goes through `native`.
    let nllbTargets: Set<String>
    private let native: any Translating
    private let nllb: any Translating

    init(native: any Translating, nllb: any Translating, nllbTargets: Set<String>) {
        self.native = native
        self.nllb = nllb
        self.nllbTargets = nllbTargets
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        // Route by target first — the user's picked language is the discriminator. If either
        // source or target is only offered by NLLB, use NLLB.
        if nllbTargets.contains(target) || nllbTargets.contains(source) {
            return try await nllb.translate(text, from: source, to: target)
        }
        return try await native.translate(text, from: source, to: target)
    }
}
