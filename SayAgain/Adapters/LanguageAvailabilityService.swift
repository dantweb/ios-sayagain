import Foundation
import Observation
import Speech
import Translation

/// Per-language availability across the two Apple frameworks the app uses.
struct LanguageAvailabilityStatus: Sendable, Equatable {
    let recognition: RecognitionAssetState
    let translation: TranslationAssetState
}

enum RecognitionAssetState: Sendable, Equatable {
    /// Model present on device — will work immediately.
    case installed
    /// Locale is known to `SpeechTranscriber` but the model is not yet on disk. Install may
    /// still fail on some devices/regions (Apple doesn't ship every model for every SKU).
    case supported
    /// `SpeechTranscriber` doesn't know this locale — cannot recognise it at all.
    case unsupported
    case unknown
}

enum TranslationAssetState: Sendable, Equatable {
    case installed
    case supported        // downloadable on first use
    case unsupported
    case unknown
}

/// Queries speech + translation availability for a set of language codes and publishes the
/// results so the UI (Settings, onboarding) can show a badge next to each language.
@Observable
@MainActor
final class LanguageAvailabilityService {

    var byCode: [String: LanguageAvailabilityStatus] = [:]

    func refresh(codes: [String], probeSource: String = "en") async {
        // Snapshot the installed set once (async property in this iOS version).
        let installedRecognition: Set<String> = Set(
            await SpeechTranscriber.installedLocales.compactMap { $0.language.languageCode?.identifier }
        )
        let availability = LanguageAvailability()
        for code in codes {
            let recognition = await Self.recognitionState(code: code, installed: installedRecognition)
            let translation = await Self.translationState(for: code, probeSource: probeSource, availability: availability)
            byCode[code] = LanguageAvailabilityStatus(recognition: recognition, translation: translation)
        }
    }

    private static func recognitionState(code: String, installed: Set<String>) async -> RecognitionAssetState {
        let candidate = Locale(identifier: code)
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) else {
            return .unsupported
        }
        let resolvedCode = resolved.language.languageCode?.identifier ?? code
        return installed.contains(resolvedCode) ? .installed : .supported
    }

    private static func translationState(
        for code: String,
        probeSource: String,
        availability: LanguageAvailability
    ) async -> TranslationAssetState {
        guard code != probeSource else { return .installed }
        let source = Locale.Language(identifier: probeSource)
        let target = Locale.Language(identifier: code)
        let status = await availability.status(from: source, to: target)
        switch status {
        case .installed:   return .installed
        case .supported:   return .supported
        case .unsupported: return .unsupported
        @unknown default:  return .unknown
        }
    }
}
