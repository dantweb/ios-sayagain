import Foundation

nonisolated final class TranslationCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let text: String
        let from: String
        let to: String
    }

    let limit: Int
    private var storage: [Key: String] = [:]
    private var order: [Key] = []               // front = least recently used

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    var count: Int { storage.count }

    func get(text: String, from: String, to: String) -> String? {
        let k = Key(text: text, from: from, to: to)
        guard let value = storage[k] else { return nil }
        touch(k)
        return value
    }

    func put(text: String, from: String, to: String, value: String) {
        guard limit > 0 else { return }
        let k = Key(text: text, from: from, to: to)
        if storage[k] != nil {
            storage[k] = value
            touch(k)
            return
        }
        storage[k] = value
        order.append(k)
        while order.count > limit {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    private func touch(_ k: Key) {
        if let idx = order.firstIndex(of: k) {
            order.remove(at: idx)
        }
        order.append(k)
    }
}
