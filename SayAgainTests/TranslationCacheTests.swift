import Foundation
import Testing
@testable import SayAgain

struct TranslationCacheTests {

    @Test func storesAndRetrieves() {
        let cache = TranslationCache(limit: 4)
        cache.put(text: "hello", from: "en", to: "es", value: "hola")
        #expect(cache.get(text: "hello", from: "en", to: "es") == "hola")
    }

    @Test func distinguishesByPair() {
        let cache = TranslationCache(limit: 4)
        cache.put(text: "hello", from: "en", to: "es", value: "hola")
        cache.put(text: "hello", from: "en", to: "fr", value: "bonjour")
        #expect(cache.get(text: "hello", from: "en", to: "es") == "hola")
        #expect(cache.get(text: "hello", from: "en", to: "fr") == "bonjour")
    }

    @Test func evictsLeastRecentlyUsedBeyondLimit() {
        let cache = TranslationCache(limit: 2)
        cache.put(text: "a", from: "en", to: "es", value: "A")
        cache.put(text: "b", from: "en", to: "es", value: "B")
        cache.put(text: "c", from: "en", to: "es", value: "C")

        #expect(cache.get(text: "a", from: "en", to: "es") == nil, "'a' should have been evicted")
        #expect(cache.get(text: "b", from: "en", to: "es") == "B")
        #expect(cache.get(text: "c", from: "en", to: "es") == "C")
    }

    @Test func touchingKeepsEntryFresh() {
        let cache = TranslationCache(limit: 2)
        cache.put(text: "a", from: "en", to: "es", value: "A")
        cache.put(text: "b", from: "en", to: "es", value: "B")
        _ = cache.get(text: "a", from: "en", to: "es")     // touch 'a'
        cache.put(text: "c", from: "en", to: "es", value: "C")

        #expect(cache.get(text: "a", from: "en", to: "es") == "A", "touching 'a' should keep it")
        #expect(cache.get(text: "b", from: "en", to: "es") == nil, "'b' should have been evicted")
    }

    @Test func zeroLimitStoresNothing() {
        let cache = TranslationCache(limit: 0)
        cache.put(text: "a", from: "en", to: "es", value: "A")
        #expect(cache.get(text: "a", from: "en", to: "es") == nil)
    }
}
