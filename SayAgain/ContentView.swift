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
            if vm.isWarmingUp {
                WarmingUpBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .animation(.easeInOut(duration: 0.2), value: vm.isWarmingUp)
        .onChange(of: vm.preferences.displayMode) { _, newValue in
            if newValue != .translationOnly {
                reader.stop()
            }
        }
        .modifier(TranslationBridgeModifier(bridge: vm.translationBridge))
    }
}

/// Shown while models are cold-loading at session start. Explains the silence between
/// hitting Record and the first line appearing (~15-60s for the Plus tier).
private struct WarmingUpBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Warming up engines…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
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
