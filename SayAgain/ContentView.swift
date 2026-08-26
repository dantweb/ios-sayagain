import SwiftUI
import Translation

struct ContentView: View {
    @State private var vm: SessionViewModel?

    var body: some View {
        Group {
            if let vm {
                if vm.preferences.hasOnboarded {
                    MainScreen(vm: vm)
                } else if vm.configuredLanguages.isEmpty {
                    LaunchSplash()
                } else {
                    OnboardingView(
                        allLanguages: vm.configuredLanguages,
                        preferences: vm.preferences,
                        onFinish: {}
                    )
                }
            } else {
                LaunchSplash()
            }
        }
        .task {
            if vm == nil {
                let newVM = SessionEnvironment.makeViewModel()
                vm = newVM
                await newVM.onAppear()
            }
        }
    }
}

private struct MainScreen: View {
    let vm: SessionViewModel
    @State private var reader = TranslationReader()
    @State private var topVisibleID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(vm: vm)
            ModeBar(vm: vm)
            if vm.preferences.displayMode == .translationOnly {
                ReadAloudBar(vm: vm, reader: reader, topVisibleID: topVisibleID)
            }
            Divider()
            TranscriptListView(
                vm: vm,
                followID: reader.currentLineID,
                topVisibleID: $topVisibleID
            )
            Divider()
            BottomBar(vm: vm)
        }
        .onChange(of: vm.preferences.displayMode) { _, newValue in
            if newValue != .translationOnly {
                reader.stop()
            }
        }
        .modifier(TranslationBridgeModifier(bridge: vm.translationBridge))
    }
}

private struct TranslationBridgeModifier: ViewModifier {
    let bridge: TranslationBridge

    func body(content: Content) -> some View {
        if bridge.currentConfig != nil {
            content.translationTask(bridge.currentConfig) { session in
                await bridge.run(with: session)
            }
        } else {
            content
        }
    }
}

private struct LaunchSplash: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("SayAgain")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
