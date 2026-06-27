import SwiftUI

struct ContentView: View {
    let playbackManager: PlaybackManager

    var body: some View {
        ToolbarView(playbackManager: playbackManager)
    }
}
