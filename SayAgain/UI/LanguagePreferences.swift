import Foundation
import Observation

enum DisplayMode: String, CaseIterable, Sendable {
    case paragraphs
    case stream
    case translationOnly

    var displayName: String {
        switch self {
        case .paragraphs:      return "Paragraphs"
        case .stream:          return "Live stream"
        case .translationOnly: return "Translation only"
        }
    }

    /// Compact label for the segmented picker in the top bar.
    var shortName: String {
        switch self {
        case .paragraphs:      return "Text"
        case .stream:          return "Stream"
        case .translationOnly: return "Translated"
        }
    }

    /// SF Symbol name for the icon-only segmented picker on the main screen.
    var iconName: String {
        switch self {
        case .paragraphs:      return "note.text"
        case .stream:          return "waveform"
        case .translationOnly: return "translate"
        }
    }
}

@Observable
@MainActor
final class LanguagePreferences {

    static let selectedKey    = "sayagain.selectedTargets.v1"
    static let onboardedKey   = "sayagain.onboarded.v1"
    static let displayModeKey = "sayagain.displayMode.v1"
    static let recognitionKey = "sayagain.recognitionLanguages.v1"

    private let defaults: UserDefaults

    private(set) var selectedTargets: Set<String>
    private(set) var hasOnboarded: Bool
    private(set) var displayMode: DisplayMode
    /// Languages the transcriber will try to recognize. One is fastest; more enables
    /// multi-language guessing at the cost of memory and latency.
    private(set) var recognitionLanguages: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.array(forKey: Self.selectedKey) as? [String], !saved.isEmpty {
            self.selectedTargets = Set(saved)
        } else {
            self.selectedTargets = []
        }
        self.hasOnboarded = defaults.bool(forKey: Self.onboardedKey)
        if let raw = defaults.string(forKey: Self.displayModeKey), let mode = DisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .paragraphs
        }
        if let saved = defaults.array(forKey: Self.recognitionKey) as? [String], !saved.isEmpty {
            self.recognitionLanguages = Set(saved)
        } else {
            self.recognitionLanguages = ["en"]
        }
    }

    func setSelectedTargets(_ codes: Set<String>) {
        selectedTargets = codes
        defaults.set(Array(codes).sorted(), forKey: Self.selectedKey)
    }

    func markOnboarded() {
        hasOnboarded = true
        defaults.set(true, forKey: Self.onboardedKey)
    }

    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        defaults.set(mode.rawValue, forKey: Self.displayModeKey)
    }

    static let recognitionLimit = 3

    func setRecognitionLanguages(_ codes: Set<String>) {
        let capped: Set<String>
        if codes.isEmpty {
            capped = ["en"]
        } else if codes.count <= Self.recognitionLimit {
            capped = codes
        } else {
            // Trim deterministically so behaviour is repeatable if pre-existing state has too many.
            capped = Set(Array(codes).sorted().prefix(Self.recognitionLimit))
        }
        recognitionLanguages = capped
        defaults.set(Array(recognitionLanguages).sorted(), forKey: Self.recognitionKey)
    }
}
