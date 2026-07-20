import Foundation
import XCTest
@testable import ReadPlease

@MainActor
final class AudioInterruptionPlaybackTests: XCTestCase {
    func testMuteLifecycleFollowsPlayPauseResumeAndFinish() {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(
            engine: engine,
            muter: muter,
            mode: { .muteChromeWhileSpeaking }
        )

        manager.play(text: "First selection")
        manager.play(text: "Replacement selection")
        XCTAssertEqual(muter.startedModes, [.muteChromeWhileSpeaking])
        XCTAssertEqual(muter.stopCallCount, 0)

        manager.pause()
        XCTAssertEqual(muter.stopCallCount, 1)

        manager.resume()
        XCTAssertEqual(
            muter.startedModes,
            [.muteChromeWhileSpeaking, .muteChromeWhileSpeaking]
        )

        engine.finish()
        XCTAssertEqual(muter.stopCallCount, 2)
    }

    func testOffModeDoesNotTouchAudioMuter() {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: engine, muter: muter, mode: { .off })

        manager.play(text: "Selection")
        manager.pause()
        manager.resume()
        manager.stop()

        XCTAssertTrue(muter.startedModes.isEmpty)
        XCTAssertEqual(muter.stopCallCount, 0)
    }

    func testModeChangeWhilePlayingStopsOldModeAndStartsNewMode() {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let mode = AudioInterruptionModeBox(.muteChromeWhileSpeaking)
        let manager = makeManager(engine: engine, muter: muter, mode: { mode.value })

        manager.play(text: "Selection")
        mode.value = .muteAllOtherAudioWhileSpeaking
        manager.audioInterruptionModeDidChange()

        XCTAssertEqual(
            muter.startedModes,
            [.muteChromeWhileSpeaking, .muteAllOtherAudioWhileSpeaking]
        )
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    func testStopCancelsPendingGlobalMuteRetry() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter(startResults: [false, false, true])
        let manager = makeManager(
            engine: engine,
            muter: muter,
            mode: { .muteAllOtherAudioWhileSpeaking },
            retryDelay: .milliseconds(10)
        )

        manager.play(text: "Selection")
        XCTAssertEqual(muter.startedModes.count, 2)

        manager.stop()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(muter.startedModes.count, 2)
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    func testGlobalMuteRetriesOnceAfterSpeechStarts() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter(startResults: [false, false, true])
        let retryStarted = expectation(description: "Global mute retry started")
        muter.onStart = { count in
            if count == 3 { retryStarted.fulfill() }
        }
        let manager = makeManager(
            engine: engine,
            muter: muter,
            mode: { .muteAllOtherAudioWhileSpeaking },
            retryDelay: .milliseconds(1)
        )

        manager.play(text: "Selection")
        await fulfillment(of: [retryStarted], timeout: 1)

        XCTAssertEqual(
            muter.startedModes,
            [
                .muteAllOtherAudioWhileSpeaking,
                .muteAllOtherAudioWhileSpeaking,
                .muteAllOtherAudioWhileSpeaking,
            ]
        )
    }

    func testChromeMuteRetriesOnceAfterSpeechStarts() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter(startResults: [false, false, true])
        let retryStarted = expectation(description: "Chrome mute retry started")
        muter.onStart = { count in
            if count == 3 { retryStarted.fulfill() }
        }
        let manager = makeManager(
            engine: engine,
            muter: muter,
            mode: { .muteChromeWhileSpeaking },
            retryDelay: .milliseconds(1)
        )

        manager.play(text: "Selection")
        await fulfillment(of: [retryStarted], timeout: 1)

        XCTAssertEqual(
            muter.startedModes,
            [
                .muteChromeWhileSpeaking,
                .muteChromeWhileSpeaking,
                .muteChromeWhileSpeaking,
            ]
        )
    }

    func testFailedChromeMuteShowsStatusAndIsCleanedUpOnStop() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter(startResults: [false, false, false])
        let retryFinished = expectation(description: "Chrome mute retry finished")
        muter.onStart = { count in
            if count == 3 { retryFinished.fulfill() }
        }
        let manager = makeManager(
            engine: engine,
            muter: muter,
            mode: { .muteChromeWhileSpeaking },
            retryDelay: .milliseconds(1)
        )

        manager.play(text: "Selection")
        await fulfillment(of: [retryFinished], timeout: 1)
        await Task.yield()

        XCTAssertEqual(
            manager.statusMessage,
            "Reading started, but Chrome audio couldn't be muted."
        )

        manager.stop()
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    private func makeManager(
        engine: InterruptionRecordingTTSEngine,
        muter: RecordingAudioMuter,
        mode: @escaping @MainActor () -> AudioInterruptionMode,
        retryDelay: Duration = .milliseconds(150)
    ) -> PlaybackManager {
        PlaybackManager(
            engine: engine,
            audioMuteController: muter,
            audioInterruptionMode: mode,
            audioMuteRetryDelay: retryDelay
        )
    }
}

@MainActor
private final class AudioInterruptionModeBox {
    var value: AudioInterruptionMode

    init(_ value: AudioInterruptionMode) {
        self.value = value
    }
}

@MainActor
private final class RecordingAudioMuter: AudioMuting {
    private var startResults: [Bool]
    private(set) var startedModes: [AudioInterruptionMode] = []
    private(set) var stopCallCount = 0
    var onStart: ((Int) -> Void)?

    init(startResults: [Bool] = []) {
        self.startResults = startResults
    }

    func start(mode: AudioInterruptionMode) -> Bool {
        startedModes.append(mode)
        onStart?(startedModes.count)
        return startResults.isEmpty ? true : startResults.removeFirst()
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class InterruptionRecordingTTSEngine: TTSEngine {
    let id = "audio-interruption-recording"
    let availableVoices: [Voice] = []
    private(set) var state: TTSEngineState = .stopped {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    var onStateChange: ((TTSEngineState) -> Void)?

    func speak(text: String, options: SpeechOptions) {
        state = .playing
    }

    func stop() {
        state = .stopped
    }

    func pause() {
        state = .paused
    }

    func resume() {
        state = .playing
    }

    func finish() {
        state = .stopped
    }
}
