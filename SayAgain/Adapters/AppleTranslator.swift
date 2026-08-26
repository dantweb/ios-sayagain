import Foundation
import Translation

nonisolated final class AppleTranslator: Translating, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: TranslationSession] = [:]

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        do {
            let session = try session(from: source, to: target)
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            print("AppleTranslator: \(source)→\(target) failed for '\(text)' — \(error)")
            throw error
        }
    }

    private func session(from source: String, to target: String) throws -> TranslationSession {
        let key = "\(source)->\(target)"
        lock.lock(); defer { lock.unlock() }
        if let existing = sessions[key] { return existing }
        let s = Locale.Language(identifier: source)
        let t = Locale.Language(identifier: target)
        let session = TranslationSession(installedSource: s, target: t)
        sessions[key] = session
        return session
    }
}
