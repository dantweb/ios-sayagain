import SwiftUI

struct OnboardingView: View {
    let allLanguages: [TranslationLanguage]
    let preferences: LanguagePreferences
    let onFinish: () -> Void

    @State private var selection: Set<String>

    init(allLanguages: [TranslationLanguage], preferences: LanguagePreferences, onFinish: @escaping () -> Void) {
        self.allLanguages = allLanguages
        self.preferences = preferences
        self.onFinish = onFinish
        // Start with everything ticked so users get the full experience by default;
        // they can pare down as they wish before continuing.
        let initial = preferences.selectedTargets.isEmpty
            ? Set(allLanguages.map(\.code))
            : preferences.selectedTargets
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Welcome to SayAgain")
                        .font(.title2.weight(.semibold))
                    Text("Pick the languages you want to translate into.\nYou can change this any time in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.top, 24)

                LanguagePickerView(allLanguages: allLanguages, selection: $selection)

                Button {
                    preferences.setSelectedTargets(selection)
                    preferences.markOnboarded()
                    onFinish()
                } label: {
                    Text(selection.isEmpty ? "Continue with none" : "Continue with \(selection.count)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
