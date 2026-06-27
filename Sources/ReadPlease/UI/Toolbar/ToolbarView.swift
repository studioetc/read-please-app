import SwiftUI

struct ToolbarView: View {
    @Environment(\.openWindow) private var openWindow
    let playbackManager: PlaybackManager

    init(playbackManager: PlaybackManager = .shared) {
        self.playbackManager = playbackManager
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

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(
                        playbackManager.statusMessage == nil ? Color.secondary : Color.orange
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
                playbackManager.handleMenuBarPrimaryAction()
            }) {
                Label(primaryActionLabel, systemImage: primaryActionSymbolName)
            }
            .accessibilityLabel(primaryActionLabel)
            .help(primaryActionHelp)

            Button(action: {
                playbackManager.stop()
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .accessibilityLabel("Stop")
            .disabled(playbackManager.state == .stopped)
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
