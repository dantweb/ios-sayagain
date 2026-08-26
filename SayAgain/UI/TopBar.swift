import SwiftUI

struct TopBar: View {
    var vm: SessionViewModel
    @State private var showingExportChoices = false
    @State private var pendingFiles: [ExportedFile] = []
    @State private var showingShareSheet = false
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .accessibilityIdentifier("sayagain.button.settings")

            // Read-only summary of the currently active target — the actual picker lives in Settings.
            if let target = vm.selectedTarget {
                Text("→ \(target.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("no translation")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingExportChoices = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .disabled(vm.finalisedLines.isEmpty)
            .accessibilityIdentifier("sayagain.button.export")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .confirmationDialog("Export as…", isPresented: $showingExportChoices, titleVisibility: .visible) {
            Button("TXT") { export(format: .txt) }
            Button("CSV") { export(format: .csv) }
            Button("Copy full text") { copyFullText() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mail and Notes send your transcript off this device. Copy and Files stay on it.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(files: pendingFiles)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                allLanguages: vm.configuredLanguages,
                recognitionLanguages: vm.recognitionLanguages,
                preferences: vm.preferences,
                vm: vm
            )
        }
    }

    private func export(format: ExportFormat) {
        guard let exporter = ExporterRegistry.default.exporter(for: format) else { return }
        do {
            let file = try exporter.export(vm.currentSnapshot, shape: currentShape)
            pendingFiles = [file]
            showingShareSheet = true
        } catch {
            // Silent fail for MVP — future: show a toast.
        }
    }

    private func copyFullText() {
        guard let exporter = ExporterRegistry.default.exporter(for: .txt),
              let file = try? exporter.export(vm.currentSnapshot, shape: currentShape),
              let text = String(data: file.data, encoding: .utf8) else { return }
        UIPasteboard.general.string = text
    }

    private var currentShape: ExportShape {
        switch vm.preferences.displayMode {
        case .paragraphs:      return .paragraphs
        case .stream:          return .stream
        case .translationOnly: return .translationOnly
        }
    }
}
