import Foundation

nonisolated struct HallucinationFilter: Sendable {
    let normalisedBlocklist: [String]

    init(blocklist: [String]) {
        // Normalise ONCE at construction — Defect 2 fix: normalise both sides identically.
        self.normalisedBlocklist = blocklist
            .map(Self.normalise(_:))
            .filter { !$0.isEmpty }
    }

    func strip(_ text: String) -> String {
        var working = Self.normalise(text)
        for phrase in normalisedBlocklist {
            working = working.replacingOccurrences(of: phrase, with: " ")
        }
        working = Self.collapseWhitespace(working).trimmingCharacters(in: .whitespacesAndNewlines)
        // Additional structural hallucination guards (Whisper's "confused" outputs):
        //   - text with no letters at all (e.g. "$$$$$$..." or ".....")
        //   - Whisper's non-speech tags in brackets/parens: "[music]", "(applause)",
        //     "(speaking in foreign language)", etc.
        if !working.contains(where: { $0.isLetter }) { return "" }
        if Self.looksLikeNonSpeechTag(working) { return "" }
        return working
    }

    /// True for strings that are just a bracketed/parenthesised non-speech marker like
    /// `[music]`, `(applause)`, `[speaking in foreign language]`.
    private static func looksLikeNonSpeechTag(_ s: String) -> Bool {
        guard let first = s.first, let last = s.last else { return false }
        let opens: Set<Character> = ["[", "(", "{"]
        let closes: Set<Character> = ["]", ")", "}"]
        guard opens.contains(first), closes.contains(last) else { return false }
        // Between brackets, only whitespace or a short lowercased phrase.
        let inner = s.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return inner.count < 60
    }

    static func normalise(_ s: String) -> String {
        var out = s.lowercased()
        while let last = out.last, last.isPunctuation || last.isWhitespace {
            out.removeLast()
        }
        return collapseWhitespace(out)
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
