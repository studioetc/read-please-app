import SwiftUI

@main
struct ReadPleaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let playbackManager = PlaybackManager.shared
    private let shortcutStore = ShortcutStore.shared

    var body: some Scene {
        MenuBarExtra("Read Please", systemImage: "text.bubble.fill") {
            VStack(spacing: 0) {
                ContentView(playbackManager: playbackManager)
                Divider()
                HStack {
                    Spacer(minLength: 0)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .frame(width: 256)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Read Please", id: "onboarding") {
            OnboardingView(coordinator: OnboardingCoordinator.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)

        Window("Scratchpad", id: "scratchpad") {
            TextInputView(playbackManager: playbackManager)
        }

        Window("Settings", id: "settings") {
            SettingsView(
                playbackManager: playbackManager,
                shortcutStore: shortcutStore,
                onboarding: OnboardingCoordinator.shared
            )
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let shortcutActionCoordinator = ShortcutActionCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApp()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ShortcutStore.shared.reloadFromDiskIfNeeded()
        OnboardingCoordinator.shared.refreshAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PlaybackManager.shared.stop()
    }

    @MainActor
    private func setupApp() {
        print("ReadPlease: App Initializing (AppDelegate)...")

        ShortcutManager.shared.onAction = { [weak self] action in
            self?.shortcutActionCoordinator.handle(action)
        }
        ShortcutStore.shared.reloadFromDiskIfNeeded()

        // Check permissions WITHOUT prompting — the onboarding Permissions step is the only place
        // that should surface a permission request. Prompting here pops the system dialog over the
        // Welcome step.
        if !TextSelectionService.shared.isAccessibilityTrusted() {
            print("WARNING: No Accessibility Permissions on Launch")
        } else {
            print("SUCCESS: Accessibility Permissions Granted")
        }
    }
}
