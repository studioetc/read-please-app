import Foundation
import XCTest
@testable import ReadPlease

@MainActor
final class AudioInterruptionPlaybackTests: XCTestCase {
    func testMuteLifecycleFollowsPlayPauseResumeAndFinish() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteChromeWhileSpeaking })
        manager.play(text: "First selection")
        await waitUntil { muter.startedModes.count == 1 }
        manager.play(text: "Replacement selection")
        await Task.yield()
        XCTAssertEqual(muter.startedModes, [.muteChromeWhileSpeaking])
        XCTAssertEqual(muter.stopCallCount, 0)
        manager.pause()
        XCTAssertEqual(muter.stopCallCount, 1)
        manager.resume()
        await waitUntil { muter.startedModes.count == 2 }
        engine.finish()
        XCTAssertEqual(muter.stopCallCount, 2)
    }

    func testOffModeDoesNotTouchAudioMuter() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: engine, muter: muter, mode: { .off })
        manager.play(text: "Selection")
        manager.pause()
        manager.resume()
        manager.stop()
        await Task.yield()
        XCTAssertTrue(muter.startedModes.isEmpty)
        XCTAssertEqual(muter.stopCallCount, 0)
    }

    func testModeChangeWhilePlayingStopsOldModeAndStartsNewMode() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let mode = AudioInterruptionModeBox(.muteChromeWhileSpeaking)
        let manager = makeManager(engine: engine, muter: muter, mode: { mode.value })
        manager.play(text: "Selection")
        await waitUntil { muter.startedModes.count == 1 }
        mode.value = .muteAllOtherAudioWhileSpeaking
        manager.audioInterruptionModeDidChange()
        await waitUntil { muter.startedModes.count == 2 }
        XCTAssertEqual(muter.startedModes, [.muteChromeWhileSpeaking, .muteAllOtherAudioWhileSpeaking])
        XCTAssertEqual(muter.stopCallCount, 1)
        manager.stop()
    }

    func testStopCancelsPendingGlobalMuteRetry() async {
        let muter = RecordingAudioMuter(startResults: [false, true])
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteAllOtherAudioWhileSpeaking }, retryDelay: .seconds(1))
        manager.play(text: "Selection")
        await waitUntil { muter.startedModes.count == 1 }
        manager.stop()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(muter.startedModes.count, 1)
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    func testMuteRetriesOnceAfterSpeechStartsForBothModes() async {
        for mode in [AudioInterruptionMode.muteAllOtherAudioWhileSpeaking, .muteChromeWhileSpeaking] {
            let muter = RecordingAudioMuter(startResults: [false, true])
            let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                      mode: { mode }, retryDelay: .milliseconds(1))
            manager.play(text: "Selection")
            await waitUntil { muter.startedModes.count == 2 }
            XCTAssertEqual(muter.startedModes, [mode, mode])
            manager.stop()
        }
    }

    func testFailedChromeMuteShowsStatusAndIsCleanedUpOnStop() async {
        let muter = RecordingAudioMuter(startResults: [false, false])
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteChromeWhileSpeaking }, retryDelay: .milliseconds(1))
        manager.play(text: "Selection")
        await waitUntil { manager.statusMessage != nil }
        XCTAssertEqual(manager.statusMessage, "Reading started, but Chrome audio couldn't be muted.")
        XCTAssertEqual(muter.startedModes.count, 2)
        manager.stop()
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    func testImmediateStopDoesNotSubmitALateMuteStart() async {
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteAllOtherAudioWhileSpeaking })
        manager.play(text: "Selection")
        manager.stop()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(muter.startedModes.isEmpty)
        XCTAssertEqual(muter.stopCallCount, 1)
    }

    func testSlowMuteDoesNotDelaySpeechOrStopAndLateResultIsIgnored() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        muter.suspendStart = true
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteAllOtherAudioWhileSpeaking })
        manager.play(text: "Selection")
        XCTAssertEqual(engine.state, .playing)
        await waitUntil { muter.pendingStart != nil }
        manager.stop()
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(muter.stopCallCount, 1)
        muter.completeStart(false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNil(manager.statusMessage)
        XCTAssertEqual(muter.startedModes.count, 1)
    }

    func testReplacementKeepsPendingMuteAndStopThenPlayStartsFreshSession() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        muter.suspendStart = true
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteChromeWhileSpeaking })
        manager.play(text: "First")
        await waitUntil { muter.pendingStart != nil }
        manager.play(text: "Replacement")
        XCTAssertEqual(muter.startedModes.count, 1)
        manager.stop()
        muter.suspendStart = false
        manager.play(text: "Fresh session")
        await waitUntil { muter.startedModes.count == 2 }
        muter.completeStart(false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(engine.state, .playing)
        XCTAssertNil(manager.statusMessage)
        XCTAssertEqual(muter.startedModes.count, 2)
        manager.stop()
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func makeManager(engine: InterruptionRecordingTTSEngine, muter: RecordingAudioMuter,
                             mode: @escaping @MainActor () -> AudioInterruptionMode,
                             retryDelay: Duration = .milliseconds(150)) -> PlaybackManager {
        PlaybackManager(engine: engine, audioMuteController: muter, audioInterruptionMode: mode,
                        audioMuteRetryDelay: retryDelay)
    }
}

@MainActor
private final class AudioInterruptionModeBox {
    var value: AudioInterruptionMode
    init(_ value: AudioInterruptionMode) { self.value = value }
}

@MainActor
private final class RecordingAudioMuter: AudioMuting {
    private var startResults: [Bool]
    private(set) var startedModes: [AudioInterruptionMode] = []
    private(set) var stopCallCount = 0
    var suspendStart = false
    var pendingStart: CheckedContinuation<Bool, Never>?
    init(startResults: [Bool] = []) { self.startResults = startResults }
    func start(mode: AudioInterruptionMode) async -> Bool {
        startedModes.append(mode)
        if suspendStart { return await withCheckedContinuation { pendingStart = $0 } }
        return startResults.isEmpty ? true : startResults.removeFirst()
    }
    func completeStart(_ result: Bool) {
        let continuation = pendingStart
        pendingStart = nil
        continuation?.resume(returning: result)
    }
    func stop() { stopCallCount += 1 }
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
    func speak(text: String, options: SpeechOptions) { state = .playing }
    func stop() { state = .stopped }
    func pause() { state = .paused }
    func resume() { state = .playing }
    func finish() { state = .stopped }
}
