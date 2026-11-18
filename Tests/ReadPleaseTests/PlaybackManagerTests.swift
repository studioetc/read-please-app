import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class PlaybackManagerTests {
    @Test func testReplacingTextDoesNotIssueSeparateStopBeforeSpeak() async {
        let engine = RecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)

        manager.play(text: "First selection")
        await Task.yield()
        manager.play(text: "Second selection")

        #expect(engine.spokenTexts == (["First selection", "Second selection"]))
        #expect(engine.stopCallCount == 0)
        #expect(manager.currentText == "Second selection")
    }

    @Test func testShortcutWithCurrentSelectionTogglesPauseAndResume() async {
        let engine = RecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)

        manager.play(text: "Current selection")
        await Task.yield()

        manager.handleShortcutPlayPause(selectedText: "Current selection")
        await Task.yield()
        #expect(engine.pauseCallCount == 1)

        manager.handleShortcutPlayPause(selectedText: "Current selection")
        #expect(engine.resumeCallCount == 1)
    }

    @Test func testShortcutWithTrailingNewlineSelectionPausesInsteadOfRestarting() async {
        let engine = RecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)

        manager.handleShortcutPlayPause(selectedText: "Triple-clicked paragraph\n")
        await Task.yield()
        manager.handleShortcutPlayPause(selectedText: "Triple-clicked paragraph\n")

        #expect(engine.spokenTexts == ["Triple-clicked paragraph"])
        #expect(engine.pauseCallCount == 1)
    }
}

@MainActor
private final class RecordingTTSEngine: TTSEngine {
    let id = "recording"
    let availableVoices: [Voice] = []
    private(set) var state: TTSEngineState = .stopped
    var onStateChange: ((TTSEngineState) -> Void)?
    private(set) var spokenTexts: [String] = []
    private(set) var stopCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0

    func speak(text: String, options: SpeechOptions) {
        spokenTexts.append(text)
        state = .playing
        onStateChange?(.playing)
    }

    func stop() {
        stopCallCount += 1
        state = .stopped
        onStateChange?(.stopped)
    }

    func pause() {
        pauseCallCount += 1
        state = .paused
        onStateChange?(.paused)
    }

    func resume() {
        resumeCallCount += 1
        state = .playing
        onStateChange?(.playing)
    }
}
