import SwiftUI

struct TranscriptListView: View {
    var vm: SessionViewModel
    /// Optional line ID to scroll to (used by Read-aloud follow). When nil, we auto-scroll to
    /// the tail on transcript mutations.
    var followID: UUID? = nil
    /// Reflects the ID of the row currently at the top of the visible area. Consumed by the
    /// Read-aloud row so speech starts from the first fully-visible line, not always the top.
    @Binding var topVisibleID: UUID?
    private static let bottomMarker = "sayagain.transcript.bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch vm.preferences.displayMode {
                    case .paragraphs:      ParagraphsMode(vm: vm)
                    case .stream:          StreamMode(vm: vm)
                    case .translationOnly: TranslationOnlyMode(vm: vm)
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomMarker)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topVisibleID, anchor: .top)
            .onChange(of: vm.finalisedLines) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.volatileText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: followID) { _, new in
                guard let new else { return }
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sayagain.list.transcript")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation { proxy.scrollTo(Self.bottomMarker, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomMarker, anchor: .bottom)
        }
    }
}

// MARK: - Mode 1: paragraphs

private struct ParagraphsMode: View {
    let vm: SessionViewModel

    var body: some View {
        ForEach(vm.finalisedLines) { fl in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("[\(fl.line.language)]")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(fl.line.text)
                        .font(.body)
                }
                ForEach(fl.translations.keys.sorted(), id: \.self) { target in
                    if let text = fl.translations[target] {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("[\(target)]")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 24)
                    }
                }
            }
        }

        if !vm.volatileText.isEmpty {
            Text(vm.volatileText)
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sayagain.text.volatile")
        }
    }
}

// MARK: - Mode 2: continuous stream

private struct StreamMode: View {
    let vm: SessionViewModel

    var body: some View {
        ForEach(vm.finalisedLines) { fl in
            Text(fl.line.text)
                .font(.body)
                .foregroundStyle(.secondary)
        }

        if !vm.volatileText.isEmpty {
            Text(vm.volatileText)
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sayagain.text.volatile")
        }
    }
}

// MARK: - Mode 3: translation only

private struct TranslationOnlyMode: View {
    let vm: SessionViewModel

    var body: some View {
        if vm.selectedTarget == nil {
            Text("Translation-only mode: pick a target language in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        ForEach(vm.finalisedLines) { fl in
            if !fl.translations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fl.translations.keys.sorted(), id: \.self) { target in
                        if let text = fl.translations[target] {
                            Text(text).font(.body)
                        }
                    }
                }
                .id(fl.id)
            }
        }
    }
}
