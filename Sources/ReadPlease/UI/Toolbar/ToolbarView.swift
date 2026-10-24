import SwiftUI

struct ToolbarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let playbackManager: PlaybackManager
    let actionCoordinator: ShortcutActionCoordinator

    init(
        playbackManager: PlaybackManager = .shared,
        actionCoordinator: ShortcutActionCoordinator = .shared
    ) {
        self.playbackManager = playbackManager
        self.actionCoordinator = actionCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    transportControls
                    Spacer(minLength: 0)
                }
                .frame(width: 192)

                Button("Read Screen Area", systemImage: "viewfinder") {
                    dismiss()
                    actionCoordinator.handle(.readScreenArea)
                }
                .disabled(actionCoordinator.isReadingScreenArea)
                .help("Select a screen area to read aloud")
                .padding(.vertical, 8)

                if actionCoordinator.screenAreaOutcome == .permissionNeeded {
                    Button("Open Screen Recording Settings") {
                        ScreenRecordingPermission.openSettings()
                    }
                    .padding(.bottom, 8)
                }

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(
                        playbackManager.statusMessage == nil && actionCoordinator.screenAreaOutcome == nil
                            ? Color.secondary : Color.orange
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(width: 256)
        }
    }

    private var transportControls: some View {
        ControlGroup {
            Button(action: {
                actionCoordinator.handleMenuBarPrimaryAction()
            }) {
                Label(primaryActionLabel, systemImage: primaryActionSymbolName)
            }
            .accessibilityLabel(primaryActionLabel)
            .help(primaryActionHelp)

            Button(action: {
                actionCoordinator.handle(.stop)
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .accessibilityLabel("Stop")
            .disabled(playbackManager.state == .stopped && !actionCoordinator.isReadingScreenArea)
            .help("Stop playback")

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }) {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Settings")
            .help("Open settings")
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    private var primaryActionLabel: String {
        switch playbackManager.state {
        case .playing:
            return "Pause"
        case .paused:
            return "Resume"
        case .stopped:
            return "Play"
        }
    }

    private var primaryActionSymbolName: String {
        switch playbackManager.state {
        case .playing:
            return "pause.fill"
        case .paused, .stopped:
            return "play.fill"
        }
    }

    private var primaryActionHelp: String {
        switch playbackManager.state {
        case .playing:
            return "Pause playback"
        case .paused:
            return "Resume playback"
        case .stopped:
            return "Read the selected text from the last active app"
        }
    }

    private var statusLine: String {
        if actionCoordinator.isReadingScreenArea {
            return "Reading screen area…"
        }
        if let outcome = actionCoordinator.screenAreaOutcome {
            return outcome.message
        }
        if let statusMessage = playbackManager.statusMessage {
            return statusMessage
        }

        switch playbackManager.state {
        case .playing:
            return "Reading selected text."
        case .paused:
            return "Playback paused."
        case .stopped:
            return "Ready to read selected text."
        }
    }
}
