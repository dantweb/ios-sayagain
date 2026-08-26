import SwiftUI

struct SettingsView: View {
    let allLanguages: [TranslationLanguage]
    let recognitionLanguages: [String]
    let preferences: LanguagePreferences
    var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var recognitionSelection: Set<String>
    @State private var currentTargetCode: String?
    @State private var availability = LanguageAvailabilityService()

    init(
        allLanguages: [TranslationLanguage],
        recognitionLanguages: [String],
        preferences: LanguagePreferences,
        vm: SessionViewModel
    ) {
        self.allLanguages = allLanguages
        self.recognitionLanguages = recognitionLanguages
        self.preferences = preferences
        self.vm = vm
        _recognitionSelection = State(initialValue: preferences.recognitionLanguages)
        _currentTargetCode = State(initialValue: vm.selectedTarget?.code)
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Default language (recognition candidates)
                Section {
                    ForEach(recognitionLanguages, id: \.self) { code in
                        let isSelected = recognitionSelection.contains(code)
                        let atLimit = recognitionSelection.count >= Self.recognitionLimit && !isSelected
                        let status = availability.byCode[code]
                        let isUnsupported = status?.recognition == .unsupported
                        Button {
                            toggleRecognition(code)
                        } label: {
                            HStack {
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code)
                                    .foregroundStyle((atLimit || isUnsupported) ? .secondary : .primary)
                                if let status {
                                    RecognitionBadge(state: status.recognition)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(atLimit || isUnsupported)
                    }
                } header: {
                    Text("Default language (\(recognitionSelection.count) of \(Self.recognitionLimit))")
                } footer: {
                    Text("Green mic = model installed and ready. Orange = the framework knows it but the model isn't on device — install may still fail depending on region. Red = unsupported. Pick up to \(Self.recognitionLimit).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: Translate to
                Section {
                    Button {
                        currentTargetCode = nil
                    } label: {
                        HStack {
                            Text("None").foregroundStyle(.primary)
                            Spacer()
                            if currentTargetCode == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    ForEach(allLanguages) { lang in
                        let status = availability.byCode[lang.code]
                        let disabled = status?.translation == .unsupported
                        Button {
                            currentTargetCode = lang.code
                        } label: {
                            HStack {
                                Text(lang.displayName).foregroundStyle(disabled ? .secondary : .primary)
                                if let status {
                                    TranslationBadge(state: status.translation)
                                }
                                Spacer()
                                if currentTargetCode == lang.code {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(disabled)
                    }
                } header: {
                    Text("Translate to")
                } footer: {
                    Text("Green = ready. Yellow = downloads on first use. Red = not offered by Apple's Translation on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                let all = Set(recognitionLanguages + allLanguages.map(\.code))
                await availability.refresh(codes: Array(all).sorted())
            }
        }
    }

    static let recognitionLimit = 3

    private func toggleRecognition(_ code: String) {
        if recognitionSelection.contains(code) {
            recognitionSelection.remove(code)
        } else if recognitionSelection.count < Self.recognitionLimit {
            recognitionSelection.insert(code)
        }
    }

    private func save() {
        preferences.setRecognitionLanguages(recognitionSelection)
        let newTarget: TranslationLanguage? = allLanguages.first(where: { $0.code == currentTargetCode })
        Task { await vm.setTarget(newTarget) }
        dismiss()
    }
}

// MARK: - Badges

private struct RecognitionBadge: View {
    let state: RecognitionAssetState
    var body: some View {
        switch state {
        case .installed:
            Image(systemName: "mic.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .supported:
            Image(systemName: "mic.badge.plus")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .unsupported:
            Image(systemName: "mic.slash.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "mic")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranslationBadge: View {
    let state: TranslationAssetState
    var body: some View {
        switch state {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .supported:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .unsupported:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
