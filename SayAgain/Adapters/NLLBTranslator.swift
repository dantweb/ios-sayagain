import Foundation

/// Stub `Translating` for language pairs Apple's `Translation` framework doesn't offer
/// (ro/hu/th ↔ anything). Slice 3 will replace the body with a CoreML NLLB inference call.
nonisolated final class NLLBTranslator: Translating, @unchecked Sendable {

    /// Bundle-relative path where the NLLB `.mlpackage` is expected. When slice 3 lands, the
    /// initializer loads it lazily on first use.
    let modelResourceName: String

    init(modelResourceName: String = "nllb-200-distilled-600M") {
        self.modelResourceName = modelResourceName
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        throw NLLBTranslator.NotAvailable(
            "NLLB model not bundled yet. See docs/sprint/09_non_native_engines.md for the " +
            "convert-and-bundle steps to add offline translation for \(source)↔\(target)."
        )
    }

    struct NotAvailable: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
