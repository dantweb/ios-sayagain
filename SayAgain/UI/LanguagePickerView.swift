import SwiftUI

/// Shared list UI for both the first-launch onboarding and the Settings sheet.
/// Keeps display consistent; the two call sites just wrap it with different chrome.
struct LanguagePickerView: View {
    let allLanguages: [TranslationLanguage]
    @Binding var selection: Set<String>

    var body: some View {
        List {
            Section {
                ForEach(allLanguages) { lang in
                    Button {
                        toggle(lang.code)
                    } label: {
                        HStack {
                            Text(lang.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(lang.code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("Only these languages will appear in the “Translate to” dropdown. First use of a language downloads its model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggle(_ code: String) {
        if selection.contains(code) {
            selection.remove(code)
        } else {
            selection.insert(code)
        }
    }
}
