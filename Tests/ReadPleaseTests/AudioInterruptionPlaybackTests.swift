import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class AudioInterruptionPlaybackTests {
    @Test func testMuteLifecycleFollowsPlayPauseResumeAndFinish() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteChromeWhileSpeaking })
        manager.play(text: "First selection")
        await waitUntil { muter.startedModes.count == 1 }
        manager.play(text: "Replacement selection")
        await Task.yield()
        #expect(muter.startedModes == ([.muteChromeWhileSpeaking]))
        #expect(muter.stopCallCount == 0)
        manager.pause()
        #expect(muter.stopCallCount == 1)
        manager.resume()
        await waitUntil { muter.startedModes.count == 2 }
        engine.finish()
        #expect(muter.stopCallCount == 2)
    }

    @Test func testOffModeDoesNotTouchAudioMuter() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: engine, muter: muter, mode: { .off })
        manager.play(text: "Selection")
        manager.pause()
        manager.resume()
        manager.stop()
        await Task.yield()
        #expect(muter.startedModes.isEmpty)
        #expect(muter.stopCallCount == 0)
    }

    @Test func testModeChangeWhilePlayingStopsOldModeAndStartsNewMode() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        let mode = AudioInterruptionModeBox(.muteChromeWhileSpeaking)
        let manager = makeManager(engine: engine, muter: muter, mode: { mode.value })
        manager.play(text: "Selection")
        await waitUntil { muter.startedModes.count == 1 }
        mode.value = .muteAllOtherAudioWhileSpeaking
        manager.audioInterruptionModeDidChange()
        await waitUntil { muter.startedModes.count == 2 }
        #expect(muter.startedModes == ([.muteChromeWhileSpeaking, .muteAllOtherAudioWhileSpeaking]))
        #expect(muter.stopCallCount == 1)
        manager.stop()
    }

    @Test func testStopCancelsPendingGlobalMuteRetry() async {
        let muter = RecordingAudioMuter(startResults: [false, true])
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteAllOtherAudioWhileSpeaking }, retryDelay: .seconds(1))
        manager.play(text: "Selection")
        await waitUntil { muter.startedModes.count == 1 }
        manager.stop()
        for _ in 0..<10 { await Task.yield() }
        #expect(muter.startedModes.count == 1)
        #expect(muter.stopCallCount == 1)
    }

    @Test func testMuteRetriesOnceAfterSpeechStartsForBothModes() async {
        for mode in [AudioInterruptionMode.muteAllOtherAudioWhileSpeaking, .muteChromeWhileSpeaking] {
            let muter = RecordingAudioMuter(startResults: [false, true])
            let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                      mode: { mode }, retryDelay: .milliseconds(1))
            manager.play(text: "Selection")
            await waitUntil { muter.startedModes.count == 2 }
            #expect(muter.startedModes == ([mode, mode]))
            manager.stop()
        }
    }

    @Test func testFailedChromeMuteShowsStatusAndIsCleanedUpOnStop() async {
        let muter = RecordingAudioMuter(startResults: [false, false])
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteChromeWhileSpeaking }, retryDelay: .milliseconds(1))
        manager.play(text: "Selection")
        await waitUntil { manager.statusMessage != nil }
        #expect(manager.statusMessage == "Reading started, but Chrome audio couldn't be muted.")
        #expect(muter.startedModes.count == 2)
        manager.stop()
        #expect(muter.stopCallCount == 1)
    }

    @Test func testImmediateStopDoesNotSubmitALateMuteStart() async {
        let muter = RecordingAudioMuter()
        let manager = makeManager(engine: InterruptionRecordingTTSEngine(), muter: muter,
                                  mode: { .muteAllOtherAudioWhileSpeaking })
        manager.play(text: "Selection")
        manager.stop()
        for _ in 0..<10 { await Task.yield() }
        #expect(muter.startedModes.isEmpty)
        #expect(muter.stopCallCount == 1)
    }

    @Test func testSlowMuteDoesNotDelaySpeechOrStopAndLateResultIsIgnored() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        muter.suspendStart = true
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteAllOtherAudioWhileSpeaking })
        manager.play(text: "Selection")
        #expect(engine.state == .playing)
        await waitUntil { muter.pendingStart != nil }
        manager.stop()
        #expect(engine.state == .stopped)
        #expect(muter.stopCallCount == 1)
        muter.completeStart(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.state == .stopped)
        #expect(manager.statusMessage == nil)
        #expect(muter.startedModes.count == 1)
    }

    @Test func testReplacementKeepsPendingMuteAndStopThenPlayStartsFreshSession() async {
        let engine = InterruptionRecordingTTSEngine()
        let muter = RecordingAudioMuter()
        muter.suspendStart = true
        let manager = makeManager(engine: engine, muter: muter, mode: { .muteChromeWhileSpeaking })
        manager.play(text: "First")
        await waitUntil { muter.pendingStart != nil }
        manager.play(text: "Replacement")
        #expect(muter.startedModes.count == 1)
        manager.stop()
        muter.suspendStart = false
        manager.play(text: "Fresh session")
        await waitUntil { muter.startedModes.count == 2 }
        muter.completeStart(false)
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.state == .playing)
        #expect(manager.statusMessage == nil)
        #expect(muter.startedModes.count == 2)
        manager.stop()
    }

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition(), sourceLocation: sourceLocation)
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
