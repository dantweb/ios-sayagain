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
        return Self.collapseWhitespace(working).trimmingCharacters(in: .whitespacesAndNewlines)
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
