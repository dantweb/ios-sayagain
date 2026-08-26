import SwiftUI

struct BottomBar: View {
    var vm: SessionViewModel
    @State private var confirmCancel = false
    @State private var confirmClean = false

    var body: some View {
        HStack(spacing: 24) {
            Button {
                confirmClean = true
            } label: {
                Text("Clean")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("sayagain.button.clean")

            Spacer()

            RecordButton(isRunning: vm.isRunning) {
                Task {
                    if vm.isRunning {
                        await vm.stop()
                    } else {
                        await vm.start()
                    }
                }
            }
            .accessibilityIdentifier("sayagain.button.record")

            Spacer()

            Button {
                confirmCancel = true
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("sayagain.button.cancel")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .confirmationDialog(
            "Discard this session? This deletes the transcript.",
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task { await vm.cancel() }
            }
            Button("Keep recording", role: .cancel) {}
        }
        .confirmationDialog(
            "Clear the screen and delete the transcript? This cannot be undone.",
            isPresented: $confirmClean,
            titleVisibility: .visible
        ) {
            Button("Clean", role: .destructive) {
                Task { await vm.clean() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct RecordButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.red : Color.green)
                    .frame(width: 72, height: 72)
                    .shadow(radius: 4)
                if isRunning {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
