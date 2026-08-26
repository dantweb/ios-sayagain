import Foundation

nonisolated protocol Translating: Sendable {
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}
