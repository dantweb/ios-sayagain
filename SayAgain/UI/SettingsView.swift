import SwiftUI

struct SettingsView: View {
    let allLanguages: [TranslationLanguage]
    let recognitionLanguages: [String]
    let plannedRecognition: [String]
    let plannedTranslation: [String]
    let preferences: LanguagePreferences
    var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var recognitionSelection: Set<String>
    @State private var currentTargetCode: String?
    @State private var availability = LanguageAvailabilityService()

    init(
        allLanguages: [TranslationLanguage],
        recognitionLanguages: [String],
        plannedRecognition: [String],
        plannedTranslation: [String],
        preferences: LanguagePreferences,
        vm: SessionViewModel
    ) {
        self.allLanguages = allLanguages
        self.recognitionLanguages = recognitionLanguages
        self.plannedRecognition = plannedRecognition
        self.plannedTranslation = plannedTranslation
        self.preferences = preferences
        self.vm = vm
        _recognitionSelection = State(initialValue: preferences.recognitionLanguages)
        _currentTargetCode = State(initialValue: vm.selectedTarget?.code)
    }

    #if SAYAGAINPLUS_TIER
    /// Injected via `TopBar` from `SessionViewModel`. Non-nil in Plus builds.
    private var downloads: ModelDownloadManager? { vm.downloadManager }
    #endif

    var body: some View {
        NavigationStack {
            Form {

                #if SAYAGAINPLUS_TIER
                if let downloads {
                    LanguagePacksSection(manager: downloads)
                }
                #endif

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

                if !plannedRecognition.isEmpty {
                    Section {
                        ForEach(plannedRecognition, id: \.self) { code in
                            HStack {
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("coming in the next version")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Planned recognition languages")
                    }
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
                        let appleStatus = availability.byCode[lang.code]
                        let coveredByLLM = isCoveredByInstalledLLM(lang.code)
                        // LLM install trumps Apple's "unsupported" — those targets are our
                        // whole reason for shipping the LLM pack.
                        let disabled = (appleStatus?.translation == .unsupported) && !coveredByLLM
                        Button {
                            currentTargetCode = lang.code
                        } label: {
                            HStack {
                                Text(lang.displayName).foregroundStyle(disabled ? .secondary : .primary)
                                if coveredByLLM {
                                    Image(systemName: "cpu.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else if let appleStatus {
                                    TranslationBadge(state: appleStatus.translation)
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
                    Text("Green mic = ready via Apple. Yellow = downloads on first use. CPU icon = handled by the installed on-device LLM. Red = not offered by Apple's Translation on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !plannedTranslation.isEmpty {
                    Section {
                        ForEach(plannedTranslation, id: \.self) { code in
                            HStack {
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("coming in the next version")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Planned translation languages")
                    }
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

    /// True when the requested target language is covered by the installed LLM pack.
    /// In base SayAgain (no `SAYAGAINPLUS_TIER`) this always returns false.
    private func isCoveredByInstalledLLM(_ code: String) -> Bool {
        #if SAYAGAINPLUS_TIER
        guard let downloads else { return false }
        guard case .installed = downloads.statuses[.llmMT] ?? .unknown else { return false }
        return vm.llmTranslationLanguages.contains(code)
        #else
        return false
        #endif
    }

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

#if SAYAGAINPLUS_TIER

/// Extra-tier download surface: two rows for the two engine packs (Whisper + LLM) with
/// download / cancel / delete affordances and live progress.
private struct LanguagePacksSection: View {
    let manager: ModelDownloadManager

    var body: some View {
        Section {
            ForEach(ModelPack.allCases) { pack in
                LanguagePackRow(pack: pack, manager: manager)
            }
        } header: {
            Text("Language Packs")
        } footer: {
            Text("Downloads run in the foreground and are cached on-device. Delete to reclaim space; you can re-download at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear { manager.refreshAll() }
    }
}

private struct LanguagePackRow: View {
    let pack: ModelPack
    let manager: ModelDownloadManager

    var body: some View {
        let status = manager.statuses[pack] ?? .unknown
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.displayName).font(.body)
                    Text(pack.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(pack.approxSizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            statusRow(status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusRow(_ status: ModelDownloadManager.Status) -> some View {
        switch status {
        case .unknown, .notInstalled:
            HStack {
                Button {
                    manager.download(pack)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
        case .downloading(let fraction):
            HStack(spacing: 12) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(role: .cancel) {
                    manager.cancel(pack)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        case .installed:
            HStack {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                Spacer()
                Button(role: .destructive) {
                    manager.delete(pack)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                Button {
                    manager.download(pack)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

#endif
