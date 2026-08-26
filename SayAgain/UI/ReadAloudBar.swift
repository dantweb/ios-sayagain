import SwiftUI

/// Row shown in Translation-only mode. A single icon-button plays / stops reading of every
/// translated line, starting from the first fully-visible row on screen. Auto-scroll follows
/// the current line so reading keeps going past the visible viewport.
struct ReadAloudBar: View {
    var vm: SessionViewModel
    @Bindable var reader: TranslationReader
    /// The ID of the row currently at the top of the transcript viewport. When Read is tapped,
    /// speech begins at this row instead of the first line in the whole transcript.
    var topVisibleID: UUID?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Image(systemName: reader.isSpeaking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(reader.isSpeaking ? Color.red : Color.accentColor)
            }
            .accessibilityLabel(reader.isSpeaking ? "Stop reading" : "Read translation aloud")
            .accessibilityHint("Reads translated lines aloud starting from the first line fully visible on screen. The view scrolls to follow the current line and continues past the visible area.")
            .accessibilityIdentifier("sayagain.button.read")

            Text(reader.isSpeaking
                 ? "Reading translated text — will keep scrolling past the screen."
                 : "Tap to read translated text aloud, starting from the top of the screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func toggle() {
        if reader.isSpeaking {
            reader.stop()
            return
        }
        // Find the starting index: first line fully visible on screen, or 0 if we can't detect.
        let startIndex: Int
        if let anchor = topVisibleID,
           let idx = vm.finalisedLines.firstIndex(where: { $0.id == anchor }) {
            startIndex = idx
        } else {
            startIndex = 0
        }

        let lines = vm.finalisedLines[startIndex...].flatMap { fl -> [TranslationReader.Line] in
            fl.translations.keys.sorted().compactMap { target in
                guard let text = fl.translations[target] else { return nil }
                return TranslationReader.Line(id: fl.id, text: text, languageCode: target)
            }
        }
        reader.speak(lines: lines)
    }
}
