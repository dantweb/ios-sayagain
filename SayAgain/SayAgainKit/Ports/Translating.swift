import Foundation

nonisolated protocol Translating: Sendable {
    func translate(_ text: String, from source: String, to target: String) async throws -> String
    /// Optional pre-warm hook. Backends that lazy-load a heavy model (MLX-LLM at ~1 GB)
    /// implement this to load into memory before the first translate call, so the user
    /// doesn't wait 30-60s on the first line of a session. Default is a no-op.
    func warmUp() async
}

extension Translating {
    func warmUp() async {}
}
