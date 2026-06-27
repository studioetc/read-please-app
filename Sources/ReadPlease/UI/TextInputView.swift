import AppKit
import SwiftUI

struct TextInputView: View {
    @State private var text = ""
    @State private var hasActivatedThisSession = false
    @FocusState private var isEditorFocused: Bool
    let playbackManager: PlaybackManager

    private static let defaultScratchpadText = """
    I've... seen things you people wouldn't believe...
    Attack ships on fire off the shoulder of Orion.
    I watched C-Beams glitter in the dark
    Near the Tannhäuser Gates.
    All those... moments... will be lost in time,
    Like tears... in... rain.
    """

    init(playbackManager: PlaybackManager = .shared) {
        self.playbackManager = playbackManager
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($isEditorFocused)
                    .font(.body)
                    .padding(8)

                if text.isEmpty {
                    Text("Type or paste text here to read aloud.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            .onAppear {
                handleScratchpadActivated()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow, window.title == "Scratchpad" else { return }
                handleScratchpadActivated()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                guard let window = notification.object as? NSWindow, window.title == "Scratchpad" else { return }
                hasActivatedThisSession = false
            }

            Divider()

            HStack {
                Button("Read Aloud", systemImage: "play.fill") {
                    playbackManager.play(text: text)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedText.isEmpty)

                Spacer()

                Text("Speed \(String(format: "%.2fx", playbackManager.currentRate))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func handleScratchpadActivated() {
        defer { hasActivatedThisSession = true }
        guard hasActivatedThisSession == false else { return }
        guard trimmedText.isEmpty else { return }
        text = Self.defaultScratchpadText
        isEditorFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }
}
