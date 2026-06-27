import AppKit
import ApplicationServices
import KeyboardShortcuts
import SwiftUI

/// Shared, observable state that drives first-run onboarding.
///
/// Option B architecture: the onboarding (stepper) window and the Settings window are *separate*
/// windows. The stepper never draws on Settings — it only mutates this coordinator, and the
/// Settings window reads `spotlight` to glow/dim its own controls. Both windows observe the same
/// `.shared` instance, so a step change in the stepper updates the highlight in Settings.
@MainActor
@Observable
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()
    private init() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    #if DEBUG
    /// A non-singleton instance pinned to a step, for `#Preview` use only.
    static func preview(_ step: Step) -> OnboardingCoordinator {
        let coordinator = OnboardingCoordinator()
        coordinator.isActive = true
        coordinator.step = step
        return coordinator
    }
    #endif

    enum Step: Int, CaseIterable {
        case welcome, permissions, shortcut, voice, done
    }

    /// Current step shown in the stepper.
    private(set) var step: Step = .welcome

    /// Whether onboarding is currently running. Settings only spotlights while this is true.
    var isActive = false

    /// Live Accessibility-trust state, refreshed by polling + on app activation.
    private(set) var accessibilityGranted: Bool

    /// Which Settings control to spotlight for the current step (nil = none).
    var spotlight: SettingsSpotlight? {
        guard isActive else { return nil }
        switch step {
        case .shortcut: return .shortcuts
        case .voice: return .voice
        default: return nil
        }
    }

    /// The user's current Play/Pause shortcut, rendered symbolically (e.g. "⌃`"). Reads
    /// ShortcutStore so the Done step reflects a shortcut changed during onboarding.
    var playPauseShortcutLabel: String {
        ShortcutStore.shared.bindings(for: .playPause).first?.shortcut.description ?? "⌃`"
    }

    // MARK: - Persistence

    private let completedKey = "hasCompletedOnboarding"
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    // MARK: - Lifecycle

    /// Begin onboarding from the first step and open the Settings window alongside the stepper.
    func begin(openSettings: () -> Void) {
        step = .welcome
        isActive = true
        refreshAccessibility()
        openSettings()
        updatePolling()
    }

    func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { finish(); return }
        step = following
        updatePolling()
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        updatePolling()
    }

    func finish() {
        isActive = false
        hasCompletedOnboarding = true
        stopPolling()
        autoAdvanceTask?.cancel()
    }

    /// Closing the stepper without finishing: clear the spotlight but don't mark onboarding done,
    /// so the user can resume later.
    func cancel() {
        isActive = false
        stopPolling()
        autoAdvanceTask?.cancel()
    }

    // MARK: - Deep links

    /// Open System Settings → Privacy & Security → Accessibility. macOS does not allow granting
    /// Accessibility inline, so this is the closest reachable pane; polling detects the grant.
    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Open System Settings → Accessibility → Spoken Content (verified anchor, see
    /// docs/voice-support-research.md §5). No anchor reaches the Manage Voices modal directly —
    /// the download list is one ⓘ click beyond this pane.
    func openVoiceDownloads() {
        open("x-apple.systempreferences:com.apple.Accessibility-Settings.extension?AX_SPOKEN_VOICE")
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Accessibility polling

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var autoAdvanceTask: Task<Void, Never>?

    /// Re-read Accessibility trust (non-prompting). When it flips to granted on the permissions
    /// step, auto-advance — so the user never has to click "re-check".
    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = trusted
        guard trusted, !wasGranted, isActive, step == .permissions else { return }
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, self.isActive, self.step == .permissions else { return }
            self.next()
        }
    }

    /// Poll only while sitting on the permissions step.
    private func updatePolling() {
        if isActive, step == .permissions { startPolling() } else { stopPolling() }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshAccessibility()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
