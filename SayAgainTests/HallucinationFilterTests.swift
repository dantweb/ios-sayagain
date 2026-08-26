import Foundation
import Testing
@testable import SayAgain

struct HallucinationFilterTests {

    // MARK: 3.8 — the FIX (Defect 2)
    @Test func hallucinationMixedWithRealSpeechIsRemovedAndSpeechSurvives() {
        let filter = HallucinationFilter(blocklist: ["thanks for watching."])
        let result = filter.strip("Thanks for watching hello world.")
        #expect(result == "hello world")
    }

    // MARK: 3.9
    @Test func lineThatIsEntirelyHallucinationYieldsEmpty() {
        let filter = HallucinationFilter(blocklist: ["thanks for watching."])
        let result = filter.strip("Thanks for watching.")
        #expect(result.isEmpty)
    }

    // Normalisation is symmetric even when only one side has trailing punctuation.
    @Test func trailingPunctuationDifferencesDoNotMatter() {
        let filter = HallucinationFilter(blocklist: ["thank you"])
        #expect(filter.strip("Thank you.").isEmpty)
        #expect(filter.strip("Thank you").isEmpty)
        #expect(filter.strip("Thank you!").isEmpty)
    }

    // Multiple blocklist entries all applied.
    @Test func multipleBlocklistEntriesAllRemoved() {
        let filter = HallucinationFilter(blocklist: ["thanks for watching.", "please subscribe"])
        let result = filter.strip("Thanks for watching please subscribe real content here.")
        #expect(result == "real content here")
    }

    // Non-hallucinated text unchanged (modulo normalisation).
    @Test func cleanTextIsPreservedModuloNormalisation() {
        let filter = HallucinationFilter(blocklist: ["thanks for watching."])
        let result = filter.strip("Actual meaningful sentence here.")
        #expect(result == "actual meaningful sentence here")
    }

    // Empty blocklist is a no-op.
    @Test func emptyBlocklistIsNoop() {
        let filter = HallucinationFilter(blocklist: [])
        let result = filter.strip("Anything at all.")
        #expect(result == "anything at all")
    }

    // Case differences on both sides are handled.
    @Test func caseDifferencesHandled() {
        let filter = HallucinationFilter(blocklist: ["THANKS FOR WATCHING"])
        let result = filter.strip("thanks for watching hello")
        #expect(result == "hello")
    }
}
