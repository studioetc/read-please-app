import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class ShortcutActionCoordinatorTests {
    @Test func testStopInvalidatesPendingSelectionBeforeItCanStartPlayback() async {
        let engine = CoordinatorRecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)
        let selection = ControlledSelectionProvider()
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            selectedTextProvider: { await selection.get() }
        )

        coordinator.handle(.playPause)
        await waitUntil { selection.callCount == 1 }

        coordinator.handle(.stop)
        selection.resolve(with: "Selection that arrived too late")
        await drainTasks()

        #expect(engine.stopCallCount == 1)
        #expect(engine.spokenTexts.isEmpty)
    }

    @Test func testDuplicatePlayPauseIsIgnoredWhileSelectionIsPending() async {
        let engine = CoordinatorRecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)
        let selection = ControlledSelectionProvider()
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            selectedTextProvider: { await selection.get() }
        )

        coordinator.handle(.playPause)
        await waitUntil { selection.callCount == 1 }
        coordinator.handle(.playPause)

        #expect(selection.callCount == 1)

        selection.resolve(with: "Current selection")
        await waitUntil { engine.spokenTexts.count == 1 }

        #expect(engine.spokenTexts == (["Current selection"]))
    }

    @Test func testDirectPlaybackActionInvalidatesPendingSelection() async {
        let engine = CoordinatorRecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)
        let selection = ControlledSelectionProvider()
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            selectedTextProvider: { await selection.get() }
        )

        coordinator.handle(.playPause)
        await waitUntil { selection.callCount == 1 }

        manager.stop()
        selection.resolve(with: "Selection after toolbar stop")
        await drainTasks()

        #expect(engine.stopCallCount == 1)
        #expect(engine.spokenTexts.isEmpty)
    }

    @Test func testPlayImmediatelyAfterStopStartsANewSelectionRequest() async {
        let engine = CoordinatorRecordingTTSEngine()
        let manager = PlaybackManager(engine: engine)
        let selection = ControlledSelectionProvider()
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            selectedTextProvider: { await selection.get() }
        )

        coordinator.handle(.playPause)
        await waitUntil { selection.callCount == 1 }

        coordinator.handle(.stop)
        coordinator.handle(.playPause)
        await waitUntil { selection.callCount == 2 }

        selection.resolve(at: 1, with: "Selection after stop")
        await waitUntil { engine.spokenTexts.count == 1 }

        selection.resolve(at: 0, with: "Cancelled selection")
        await drainTasks()

        #expect(engine.spokenTexts == (["Selection after stop"]))
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition was not met", sourceLocation: sourceLocation)
    }

    private func drainTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
private final class ControlledSelectionProvider {
    private var continuations: [CheckedContinuation<String?, Never>?] = []
    private(set) var callCount = 0

    func get() async -> String? {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resolve(with text: String?) {
        guard let index = continuations.firstIndex(where: { $0 != nil }) else { return }
        resolve(at: index, with: text)
    }

    func resolve(at index: Int, with text: String?) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else {
            return
        }
        continuations[index] = nil
        continuation.resume(returning: text)
    }
}

@MainActor
private final class CoordinatorRecordingTTSEngine: TTSEngine {
    let id = "coordinator-recording"
    let availableVoices: [Voice] = []
    private(set) var state: TTSEngineState = .stopped
    var onStateChange: ((TTSEngineState) -> Void)?
    private(set) var spokenTexts: [String] = []
    private(set) var stopCallCount = 0

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
        state = .paused
        onStateChange?(.paused)
    }

    func resume() {
        state = .playing
        onStateChange?(.playing)
    }
}
