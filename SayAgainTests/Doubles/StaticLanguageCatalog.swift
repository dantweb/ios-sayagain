import Foundation
@testable import SayAgain

struct StaticLanguageCatalog: LanguageCatalog {
    let languages: [TranslationLanguage]

    func availableTargets() async -> [TranslationLanguage] { languages }
}
