import AppKit
import SwiftUI

/// The first-run stepper window. Its own window (Option B) — it drives `OnboardingCoordinator`,
/// which the separate Settings window observes to spotlight the matching control.
struct OnboardingView: View {
    let coordinator: OnboardingCoordinator

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Top-aligned flow on a strict 8-pt scale. The window height follows the content
        // (windowResizability(.contentSize) on the scene) instead of being pinned, so no step
        // ever leaves an empty band to balance.
        VStack(alignment: .leading, spacing: 0) {
            header
            hero
            Text(stepTitle)
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 24)
            Text(stepMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if hasActionArea {
                actionArea.padding(.top, 16)
            }
            footer.padding(.top, 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(width: 520)
        .background(backgroundGradient)
        .onAppear {
            // Already running (e.g. a #Preview that pinned a step) — don't reset to Welcome.
            guard !coordinator.isActive else { return }
            if coordinator.hasCompletedOnboarding {
                dismiss()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                coordinator.begin(openSettings: { openWindow(id: "settings") })
            }
        }
        // Closing the stepper (red button / Cmd-W) clears the Settings spotlight.
        .onDisappear { coordinator.cancel() }
    }

    private var hasActionArea: Bool {
        coordinator.step != .welcome
    }

    // MARK: - Header / hero

    private var header: some View {
        // Trailing-aligned via a single frame modifier (not HStack + Spacer). Kept in the layout
        // on every step via opacity so the header height stays constant.
        Button("Skip") { finish() }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(coordinator.step == .done ? 0 : 1)
            .disabled(coordinator.step == .done)
            .padding(.bottom, 8)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            if coordinator.step == .shortcut {
                ShortcutKeysView()
            } else {
                Image(systemName: heroSymbol)
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Per-step action area

    @ViewBuilder
    private var actionArea: some View {
        switch coordinator.step {
        case .permissions:
            DeepLinkActionBlock(
                buttonTitle: "Open System Settings",
                statusText: coordinator.accessibilityGranted
                    ? "Accessibility granted" : "Accessibility — not granted",
                statusDone: coordinator.accessibilityGranted,
                hint: "Find Read Please in the list and turn it on.",
                action: coordinator.openAccessibilitySettings
            )
        case .voice:
            DeepLinkActionBlock(
                buttonTitle: "Get higher-quality voices…",
                hint: "In Settings, click the ⓘ next to System Voice → Manage Voices to download.",
                action: coordinator.openVoiceDownloads
            )
        case .shortcut:
            Label(
                "Tip: Assign your shortcut to a mouse button in Karabiner-Elements or your mouse’s own software for one-click reading.",
                systemImage: "computermouse"
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        case .done:
            Text("Select this text and press the shortcut to read aloud")
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        default:
            EmptyView()
        }
    }

    // MARK: - Footer (dots + nav)

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(OnboardingCoordinator.Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(dotColor(for: s))
                        .frame(width: s == coordinator.step ? 20 : 7, height: 7)
                }
            }
            Spacer()
            if coordinator.step != .welcome {
                Button("Back") { coordinator.back() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func primaryAction() {
        if coordinator.step == .done { finish() } else { coordinator.next() }
    }

    private func finish() {
        coordinator.finish()
        dismiss()
    }

    // MARK: - Per-step content

    private var stepTitle: String {
        switch coordinator.step {
        case .welcome: "Welcome to Read Please"
        case .permissions: "One permission to grant"
        case .shortcut: "Set your shortcut"
        case .voice: "Choose a voice"
        case .done: "You’re all set"
        }
    }

    private var stepMessage: LocalizedStringKey {
        switch coordinator.step {
        case .welcome:
            "Read Please speaks any text you select in any app. Select text, press a key, listen. Let’s set it up."
        case .permissions:
            "It only reads the text you’ve selected, 100% local, on-device."
        case .shortcut:
            "Press **⌃`** to play or pause, **⌃1** to stop. Or customize the shortcuts in the settings."
        case .voice:
            "Read Please uses your Mac’s built-in voices. For more natural-sounding speech, download Apple’s **Enhanced** or **Premium** voices in System Settings."
        case .done:
            "Select some text, press **\(coordinator.playPauseShortcutLabel)**, and listen."
        }
    }

    private var heroSymbol: String {
        switch coordinator.step {
        case .welcome: "speaker.wave.2.fill"
        case .permissions: "lock.shield"
        case .shortcut: "keyboard"
        case .voice: "person.wave.2.fill"
        case .done: "checkmark.seal.fill"
        }
    }

    private var primaryTitle: String {
        switch coordinator.step {
        case .welcome: "Get Started"
        case .done: "Done"
        default: "Continue"
        }
    }

    private func dotColor(for s: OnboardingCoordinator.Step) -> Color {
        if s == coordinator.step { return .accentColor }
        if s.rawValue < coordinator.step.rawValue { return .accentColor.opacity(0.5) }
        return Color.secondary.opacity(0.3)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Reusable "open a Settings pane" block — used by both the Permissions and Voice steps, since
/// both follow the same shape: deep-link button → (optional live status) → guidance for the one
/// click we can't automate.
struct DeepLinkActionBlock: View {
    let buttonTitle: String
    var statusText: String? = nil
    var statusDone: Bool = false
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                if let statusText {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDone ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Approach A — the Control + backtick shortcut graphic for the hero, composed from `Text`
/// (system font renders ⌃ ~ `) inside a stroked `RoundedRectangle`. No bezier paths, no assets.
/// Point sizes mirror `Assets/shortcut-keys.svg` 1:1 so it drops in where the SF Symbol sits.
private struct ShortcutKeysView: View {
    var body: some View {
        HStack(spacing: 24) {
            controlKey
            Text("+")
                .font(.system(size: 32, weight: .medium, design: .rounded))
            backtickKey
        }
        .foregroundStyle(.white)
    }

    /// Wide cap: ⌃ top-left, "control" bottom-left (left-aligned, as on a real keycap).
    private var controlKey: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(lineWidth: 3.5)
            .frame(width: 120, height: 96)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("⌃").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Text("control").font(.system(size: 19, weight: .semibold, design: .rounded))
                }
                .padding(.leading, 20)
                .padding(.vertical, 12)
            }
    }

    /// Square cap: ~ over `, stacked and centered.
    private var backtickKey: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(lineWidth: 3.5)
            .frame(width: 92, height: 96)
            .overlay {
                VStack(spacing: 0) {
                    Text("~").font(.system(size: 32, weight: .semibold, design: .rounded)).offset(y: -2)
                    Spacer(minLength: 0)
                    Text("`").font(.system(size: 36, weight: .semibold, design: .rounded)).offset(y: 4)
                }
                .padding(.vertical, 14)
            }
    }
}

#if DEBUG
#Preview("Welcome") { OnboardingView(coordinator: .preview(.welcome)) }
#Preview("Permissions") { OnboardingView(coordinator: .preview(.permissions)) }
#Preview("Shortcut") { OnboardingView(coordinator: .preview(.shortcut)) }
#Preview("Voice") { OnboardingView(coordinator: .preview(.voice)) }
#Preview("Done") { OnboardingView(coordinator: .preview(.done)) }
#endif
