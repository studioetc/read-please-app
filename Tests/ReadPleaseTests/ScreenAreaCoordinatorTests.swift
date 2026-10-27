import CoreGraphics
import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class ScreenAreaCoordinatorTests {
    @Test func testPipelineOrdersFormatsAndSpeaksFreshText() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let (coordinator, _, engine) = makeCoordinator(capture: capture)
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(engine.spokenTexts == (["An example appears."]))
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testPipelineKeepsDenseTableRowsSeparate() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let (coordinator, _, engine) = makeCoordinator(capture: capture, recognize: { _ in
            [["Item", "Qty", "Price"], ["Pens", "12", "3.50"], ["Paper", "5", "8.00"]]
                .enumerated().flatMap { row, cells in
                    cells.enumerated().map { column, text in
                        OCRLine(text: text, box: CGRect(x: column * 180, y: row * 24, width: 60, height: 18))
                    }
                }
        })
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(engine.spokenTexts == (["Item Qty Price\nPens 12 3.50\nPaper 5 8.00"]))
    }

    @Test func testDuplicatePressIsIgnoredWhileCaptureIsPending() async throws {
        let capture = FakeRegionCapture()
        let (coordinator, _, engine) = makeCoordinator(capture: capture)
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 1 }
        coordinator.handle(.readScreenArea)
        #expect(capture.callCount == 1)
        capture.resolve(.success(try region()))
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(engine.spokenTexts.count == 1)
    }

    @Test func testStopDuringCaptureCancelsAndNeverRecognizesOrSpeaksLate() async throws {
        let capture = FakeRegionCapture()
        let recognition = ControlledRecognition()
        let (coordinator, _, engine) = makeCoordinator(capture: capture, recognize: { await recognition.get($0) })
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 1 }
        coordinator.handle(.stop)
        capture.resolve(.success(try region()))
        await drainTasks()
        let calls = await recognition.callCount
        #expect(calls == 0)
        #expect(capture.cancelledReturnCount == 1)
        #expect(engine.spokenTexts.isEmpty)
        #expect(engine.stopCallCount == 1)
        #expect(!coordinator.isReadingScreenArea)
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testStopDuringOCRCancelsAndIgnoresSecondPressWhileBusy() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let recognition = ControlledRecognition()
        let (coordinator, _, engine) = makeCoordinator(capture: capture, recognize: { await recognition.get($0) })
        coordinator.handle(.readScreenArea)
        await waitUntil { await recognition.callCount == 1 }
        coordinator.handle(.readScreenArea)
        #expect(capture.callCount == 1)
        coordinator.handle(.stop)
        await recognition.resolve(with: Self.recognizedLines)
        await drainTasks()
        #expect(engine.spokenTexts.isEmpty)
        #expect(!coordinator.isReadingScreenArea)
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testOldCaptureCleanupCannotClearNewCaptureAfterStop() async throws {
        let capture = FakeRegionCapture()
        let (coordinator, _, engine) = makeCoordinator(capture: capture)
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 1 }
        coordinator.handle(.stop)
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 2 }
        capture.resolve(.success(try region()), at: 0)
        await drainTasks()
        #expect(coordinator.isReadingScreenArea)
        coordinator.handle(.readScreenArea)
        #expect(capture.callCount == 2)
        capture.resolve(.success(try region()), at: 1)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(engine.spokenTexts == (["An example appears."]))
    }

    @Test func testDirectPlaybackRevisionInvalidatesPendingOCRResult() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let recognition = ControlledRecognition()
        let (coordinator, manager, engine) = makeCoordinator(capture: capture, recognize: { await recognition.get($0) })
        coordinator.handle(.readScreenArea)
        await waitUntil { await recognition.callCount == 1 }
        manager.play(text: "Newer scratchpad text")
        await recognition.resolve(with: Self.recognizedLines)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(engine.spokenTexts == (["Newer scratchpad text"]))
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testDirectStopInvalidatesLateCaptureError() async {
        let capture = FakeRegionCapture()
        let (coordinator, manager, engine) = makeCoordinator(capture: capture)
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 1 }
        manager.stop()
        capture.resolve(.failure(.failed("Late failure")))
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(coordinator.screenAreaOutcome == nil)
        #expect(engine.spokenTexts.isEmpty)
    }

    @Test func testSelectionActionSupersedesPendingCapture() async throws {
        let capture = FakeRegionCapture()
        let (coordinator, _, engine) = makeCoordinator(capture: capture)
        coordinator.handle(.readScreenArea)
        await waitUntil { capture.callCount == 1 }
        coordinator.handle(.playPause)
        await waitUntil { engine.spokenTexts.count == 1 }
        capture.resolve(.success(try region()))
        await drainTasks()
        #expect(engine.spokenTexts == (["Selected text"]))
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testCaptureActionSupersedesPendingSelection() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let engine = ScreenAreaRecordingEngine()
        let manager = PlaybackManager(engine: engine, audioMuteController: ScreenAreaNoAudioMuter(), audioInterruptionMode: { .off })
        var selectionContinuation: CheckedContinuation<String?, Never>?
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            screenAreaReader: ScreenAreaReader(captureBackend: capture, recognize: { _ in Self.recognizedLines }),
            selectedTextProvider: { await withCheckedContinuation { selectionContinuation = $0 } }
        )
        coordinator.handle(.playPause)
        await waitUntil { selectionContinuation != nil }
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        selectionContinuation?.resume(returning: "Old selected text")
        await drainTasks()
        #expect(engine.spokenTexts == (["An example appears."]))
    }

    @Test func testRecognitionCancellationIsSilentAndFailureHasDistinctOutcome() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let (cancelled, _, engine) = makeCoordinator(capture: capture, recognize: { _ in throw CancellationError() })
        cancelled.handle(.readScreenArea)
        await waitUntil { !cancelled.isReadingScreenArea }
        #expect(cancelled.screenAreaOutcome == nil)
        #expect(engine.spokenTexts.isEmpty)
        let (failed, _, failedEngine) = makeCoordinator(capture: capture, recognize: { _ in
            throw NSError(domain: "OCRFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recognition failed"])
        })
        failed.handle(.readScreenArea)
        await waitUntil { !failed.isReadingScreenArea }
        #expect(failed.screenAreaOutcome == (.failed("Recognition failed")))
        #expect(failedEngine.spokenTexts.isEmpty)
    }

    @Test func testAbsentBackendIsFriendlyAndDoesNotSpeak() async {
        let (coordinator, _, engine) = makeCoordinator(capture: nil)
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(coordinator.screenAreaOutcome == .notAvailableYet)
        #expect(engine.spokenTexts.isEmpty)
    }

    @Test func testNewPlaybackHidesObsoleteScreenAreaOutcome() async {
        let (coordinator, manager, _) = makeCoordinator(capture: nil)
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(coordinator.screenAreaOutcome == .notAvailableYet)
        manager.play(text: "A newer scratchpad reading")
        #expect(coordinator.screenAreaOutcome == nil)
    }

    @Test func testEmptyOCRHasDistinctNoTextOutcome() async throws {
        let capture = FakeRegionCapture(result: .success(try region()))
        let (coordinator, _, engine) = makeCoordinator(capture: capture, recognize: { _ in [] })
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        #expect(coordinator.screenAreaOutcome == .noTextFound)
        #expect(engine.spokenTexts.isEmpty)
    }

    @Test func testCaptureOutcomesDistinguishCancellationPermissionAndFailure() async {
        for (error, expected): (RegionCaptureError, ScreenAreaReadOutcome?) in [
            (.cancelled, nil), (.permissionNeeded, .permissionNeeded), (.failed("Fixture error"), .failed("Fixture error")),
        ] {
            let capture = FakeRegionCapture(result: .failure(error))
            let (coordinator, _, engine) = makeCoordinator(capture: capture)
            coordinator.handle(.readScreenArea)
            await waitUntil { !coordinator.isReadingScreenArea }
            #expect(coordinator.screenAreaOutcome == expected)
            #expect(engine.spokenTexts.isEmpty)
        }
    }

    nonisolated private static let recognizedLines = [
        OCRLine(text: "appears.", box: CGRect(x: 0, y: 24, width: 200, height: 20)),
        OCRLine(text: "An example", box: CGRect(x: 0, y: 0, width: 200, height: 20)),
    ]

    private func makeCoordinator(
        capture: (any RegionCapturing)?,
        recognize: @escaping @Sendable (CapturedRegion) async throws -> [OCRLine] = { _ in recognizedLines }
    ) -> (ShortcutActionCoordinator, PlaybackManager, ScreenAreaRecordingEngine) {
        let engine = ScreenAreaRecordingEngine()
        let manager = PlaybackManager(engine: engine, audioMuteController: ScreenAreaNoAudioMuter(), audioInterruptionMode: { .off })
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            screenAreaReader: ScreenAreaReader(captureBackend: capture, recognize: recognize),
            selectedTextProvider: { "Selected text" }
        )
        return (coordinator, manager, engine)
    }

    private func region() throws -> CapturedRegion {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return CapturedRegion(image: try #require(context.makeImage()), pixelsPerPoint: 2)
    }

    private func waitUntil(
        _ condition: @MainActor () async -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<1000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Condition was not met", sourceLocation: sourceLocation)
    }

    private func drainTasks() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

/// Deliberately returns after cancellation so tests also exercise uncooperative backends.
@MainActor
private final class FakeRegionCapture: RegionCapturing {
    let result: Result<CapturedRegion, RegionCaptureError>?
    private var continuations: [CheckedContinuation<CapturedRegion, any Error>?] = []
    private(set) var callCount = 0
    private(set) var cancelledReturnCount = 0

    init(result: Result<CapturedRegion, RegionCaptureError>? = nil) {
        self.result = result
    }

    func captureRegion() async throws -> CapturedRegion {
        callCount += 1
        if let result { return try result.get() }
        let region: CapturedRegion = try await withCheckedThrowingContinuation { continuations.append($0) }
        if Task.isCancelled { cancelledReturnCount += 1 }
        return region
    }

    func resolve(_ result: Result<CapturedRegion, RegionCaptureError>, at index: Int = 0) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else { return }
        continuations[index] = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}

private actor ControlledRecognition {
    private var continuation: CheckedContinuation<[OCRLine], Never>?
    private(set) var callCount = 0

    func get(_ region: CapturedRegion) async -> [OCRLine] {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(with lines: [OCRLine]) {
        continuation?.resume(returning: lines)
        continuation = nil
    }
}

@MainActor
private final class ScreenAreaNoAudioMuter: AudioMuting {
    func start(mode: AudioInterruptionMode) -> Bool { false }
    func stop() {}
}

@MainActor
private final class ScreenAreaRecordingEngine: TTSEngine {
    let id = "screen-area-recording"
    let availableVoices: [Voice] = []
    private(set) var state: TTSEngineState = .stopped
    var onStateChange: ((TTSEngineState) -> Void)?
    private(set) var spokenTexts: [String] = []
    private(set) var stopCallCount = 0

    func speak(text: String, options: SpeechOptions) {
        spokenTexts.append(text)
        state = .playing
        onStateChange?(state)
    }

    func stop() {
        stopCallCount += 1
        state = .stopped
        onStateChange?(state)
    }

    func pause() {
        state = .paused
        onStateChange?(state)
    }

    func resume() {
        state = .playing
        onStateChange?(state)
    }
}
