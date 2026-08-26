import SwiftUI

/// Segmented icon picker for the transcript display mode — Paragraphs / Stream / Translated.
/// Only one is active at a time; selection persists via `LanguagePreferences`.
struct ModeBar: View {
    var vm: SessionViewModel

    var body: some View {
        Picker("Display mode", selection: modeBinding) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Image(systemName: mode.iconName)
                    .accessibilityLabel(mode.displayName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("sayagain.picker.mode")
    }

    private var modeBinding: Binding<DisplayMode> {
        Binding(
            get: { vm.preferences.displayMode },
            set: { vm.preferences.setDisplayMode($0) }
        )
    }
}
