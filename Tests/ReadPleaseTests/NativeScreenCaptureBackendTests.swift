import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ReadPlease

@MainActor
final class NativeScreenCaptureBackendTests: XCTestCase {
    func testArgumentsUniquePrivateDirectoriesAndEscapeCleanup() async throws {
        let runner = FakeScreenCaptureRunner { request in
            let attributes = try FileManager.default.attributesOfItem(atPath: request.output.deletingLastPathComponent().path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            return 0
        }
        let backend = makeBackend(runner: runner, hasPermission: { true })
        await assertError(.cancelled, backend: backend)
        await assertError(.cancelled, backend: backend)
        let calls = await runner.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertNotEqual(calls[0].output, calls[1].output)
        for call in calls {
            XCTAssertEqual(call.executableURL.path, "/usr/sbin/screencapture")
            XCTAssertEqual(Array(call.arguments.dropLast()), ["-i", "-x", "-s", "-t", "png"])
            XCTAssertFalse(call.arguments.contains("-c"))
            XCTAssertEqual(call.output.pathExtension, "png")
            assertRemoved(call)
        }
    }

    func testExitOneWithoutDiagnosticOrFileIsCancelled() async {
        let runner = FakeScreenCaptureRunner { _ in 1 }
        await assertError(.cancelled, runner: runner)
        await assertAllRemoved(runner)
    }

    func testMissingFileWithoutPermissionNeedsSettings() async {
        let runner = FakeScreenCaptureRunner { _ in 0 }
        await assertError(.permissionNeeded, runner: runner, hasPermission: false)
        await assertAllRemoved(runner)
    }

    func testDeniedPreflightRequestsOnceAndNeverStartsSelector() async {
        let runner = FakeScreenCaptureRunner { _ in XCTFail("Must not capture without permission"); return 0 }
        var requests = 0
        let backend = makeBackend(runner: runner, hasPermission: { false }, requestPermission: { requests += 1; return false })
        await assertError(.permissionNeeded, backend: backend)
        await assertError(.permissionNeeded, backend: backend)
        XCTAssertEqual(requests, 1)
        let count = await runner.calls.count
        XCTAssertEqual(count, 0)
    }

    func testSynchronousPermissionGrantStillSkipsThisSelector() async {
        let runner = FakeScreenCaptureRunner { _ in XCTFail("Retry must be explicit"); return 0 }
        var requests = 0
        let backend = makeBackend(runner: runner, hasPermission: { false }, requestPermission: { requests += 1; return true })
        await assertError(.permissionNeeded, backend: backend)
        XCTAssertEqual(requests, 1)
        let count = await runner.calls.count
        XCTAssertEqual(count, 0)
    }

    func testReadableWallpaperIsNotAcceptedWithoutPermission() async {
        let runner = FakeScreenCaptureRunner { request in
            try Self.writePNG(to: request.output)
            return 0
        }
        await assertError(.permissionNeeded, runner: runner, hasPermission: false)
        await assertAllRemoved(runner)
    }

    func testRevokedPermissionTakesPriorityOverNonzeroExitAndStderr() async {
        let runner = FakeScreenCaptureRunner { request in
            try Data(" denied by helper \n".utf8).write(to: request.stderrURL)
            return 1
        }
        await assertError(.permissionNeeded, runner: runner, hasPermission: false)
        await assertAllRemoved(runner)
    }

    func testUnexpectedExitWithoutDiagnosticIsFailure() async {
        let runner = FakeScreenCaptureRunner { _ in 2 }
        await assertError(.failed("screencapture exited with status 2."), runner: runner)
        await assertAllRemoved(runner)
    }

    func testNonzeroExitDoesNotAcceptPartialPNG() async {
        let runner = FakeScreenCaptureRunner { request in
            try Self.writePNG(to: request.output)
            return 1
        }
        await assertError(.failed("screencapture exited with status 1."), runner: runner)
        await assertAllRemoved(runner)
    }

    func testLaunchFailureCleansPartialFiles() async {
        let runner = FakeScreenCaptureRunner { request in
            try Data("partial".utf8).write(to: request.output)
            throw NSError(domain: "CaptureTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot launch helper"])
        }
        await assertError(.failed("Cannot launch helper"), runner: runner)
        await assertAllRemoved(runner)
    }

    func testUnreadablePNGWithPermissionFailsAndIsRemoved() async {
        let runner = FakeScreenCaptureRunner { request in
            try Data("not a PNG".utf8).write(to: request.output)
            return 0
        }
        await assertError(.failed("The captured PNG could not be read."), runner: runner)
        await assertAllRemoved(runner)
    }

    func testUnreadablePNGWithoutPermissionNeedsSettings() async {
        let runner = FakeScreenCaptureRunner { request in
            try Data("not a PNG".utf8).write(to: request.output)
            return 0
        }
        await assertError(.permissionNeeded, runner: runner, hasPermission: false)
        await assertAllRemoved(runner)
    }

    func testSuccessLoadsImageAndDPIBeforeRemovingFiles() async throws {
        let runner = FakeScreenCaptureRunner { request in
            try Self.writePNG(to: request.output, dpi: 144)
            return 0
        }
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let region = try await backend.captureRegion()
        XCTAssertEqual(region.image.width, 20)
        XCTAssertEqual(region.image.height, 10)
        XCTAssertEqual(region.pixelsPerPoint, 2, accuracy: 0.01)
        XCTAssertNotNil(region.image.dataProvider?.data)
        await assertAllRemoved(runner)
    }

    func testMissingDPIFallsBackToOne() async throws {
        let runner = FakeScreenCaptureRunner { request in
            try Self.writePNG(to: request.output)
            return 0
        }
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let region = try await backend.captureRegion()
        XCTAssertEqual(region.pixelsPerPoint, 1, accuracy: 0.01)
        await assertAllRemoved(runner)
    }

    func testReentryRejectedWhileProcessIsPending() async throws {
        let runner = FakeScreenCaptureRunner()
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let first = Task { try await backend.captureRegion() }
        await waitUntil { await runner.calls.count == 1 }
        await assertError(.cancelled, backend: backend)
        let count = await runner.calls.count
        XCTAssertEqual(count, 1)
        await runner.finish()
        await assertCancelled(first)
        await assertAllRemoved(runner)
    }

    func testTaskCancellationTerminatesAndKeepsGateUntilExit() async throws {
        let runner = FakeScreenCaptureRunner()
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let first = Task { try await backend.captureRegion() }
        await waitUntil { await runner.calls.count == 1 }
        let calls = await runner.calls
        let request = try XCTUnwrap(calls.first)
        try Data("partial".utf8).write(to: request.output)
        first.cancel()
        await waitUntil { await runner.terminationRequested }
        // Simulate slow selector teardown: do not release the gate or remove an open output yet.
        await assertError(.cancelled, backend: backend)
        XCTAssertTrue(FileManager.default.fileExists(atPath: request.output.path))
        await runner.finish()
        await assertCancelled(first)
        assertRemoved(request)
        // A fresh capture is accepted after cancellation fully finishes.
        let next = Task { try await backend.captureRegion() }
        await waitUntil { await runner.calls.count == 2 }
        await runner.finish()
        await assertCancelled(next)
        await assertAllRemoved(runner)
    }

    func testStopThenImmediateRepressIsSilentWhileSelectorTearsDown() async throws {
        let runner = FakeScreenCaptureRunner()
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let engine = NativeCaptureTestEngine()
        let manager = PlaybackManager(engine: engine, audioMuteController: NativeCaptureTestMuter(), audioInterruptionMode: { .off })
        let coordinator = ShortcutActionCoordinator(
            playbackManager: manager,
            screenAreaReader: ScreenAreaReader(captureBackend: backend, recognize: { _ in
                XCTFail("Cancelled capture must never reach OCR")
                return []
            }), selectedTextProvider: { nil }
        )
        coordinator.handle(.readScreenArea)
        await waitUntil { await runner.calls.count == 1 }
        coordinator.handle(.stop)
        XCTAssertFalse(coordinator.isReadingScreenArea)
        coordinator.handle(.readScreenArea)
        await waitUntil { !coordinator.isReadingScreenArea }
        await waitUntil { await runner.terminationRequested }
        XCTAssertNil(coordinator.screenAreaOutcome)
        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        let request = try XCTUnwrap(calls.first)
        await runner.finish()
        await waitUntil { !FileManager.default.fileExists(atPath: request.output.deletingLastPathComponent().path) }
        XCTAssertNil(coordinator.screenAreaOutcome)
        await assertAllRemoved(runner)
    }

    func testAlreadyCancelledTaskNeverStartsProcess() async {
        let runner = FakeScreenCaptureRunner { _ in 0 }
        let backend = makeBackend(runner: runner, hasPermission: { true })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await backend.captureRegion()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || error as? RegionCaptureError == .cancelled) }
        let count = await runner.calls.count
        XCTAssertEqual(count, 0)
    }

    func testWaitsForControlReleaseBeforeLaunching() async throws {
        let runner = FakeScreenCaptureRunner { _ in 0 }
        let control = NativeCaptureControlState()
        let backend = makeBackend(runner: runner, isControlHeld: { control.polls += 1; return control.isHeld })
        let capture = Task { try await backend.captureRegion() }
        await waitUntil { control.polls > 0 }
        let pendingCount = await runner.calls.count
        XCTAssertEqual(pendingCount, 0)
        control.isHeld = false
        await assertCancelled(capture)
        let completedCount = await runner.calls.count
        XCTAssertEqual(completedCount, 1)
        await assertAllRemoved(runner)
    }

    func testControlReleaseTimeoutNeverLaunchesSelector() async {
        let runner = FakeScreenCaptureRunner { _ in 0 }
        let backend = makeBackend(runner: runner, isControlHeld: { true }, modifierReleaseTimeout: .milliseconds(25))
        await assertError(.failed("Release Control, then try Read Screen Area again."), backend: backend)
        let count = await runner.calls.count
        XCTAssertEqual(count, 0)
    }

    func testCancellationWhileWaitingForControlNeverLaunchesSelector() async {
        let runner = FakeScreenCaptureRunner { _ in 0 }
        var polls = 0
        let backend = makeBackend(runner: runner, isControlHeld: { polls += 1; return true })
        let capture = Task { try await backend.captureRegion() }
        await waitUntil { polls > 0 }
        capture.cancel()
        await assertCancelled(capture)
        let count = await runner.calls.count
        XCTAssertEqual(count, 0)
    }

    func testChangedClipboardCountWithNoFileReportsPossibleControlRedirect() async {
        for status: Int32 in [0, 1] {
            let runner = FakeScreenCaptureRunner { _ in status }
            var countReads = 0
            let backend = makeBackend(runner: runner, clipboardChangeCount: {
                countReads += 1
                return countReads == 1 ? 10 : 11
            })
            await assertError(.failed("Release Control while selecting. The capture may have gone to the clipboard."), backend: backend)
            XCTAssertEqual(countReads, 2)
            await assertAllRemoved(runner)
        }
    }

    func testNonzeroDiagnosticStillFailsWhenPermissionIsGranted() async {
        let runner = FakeScreenCaptureRunner { request in
            try Data("helper failed".utf8).write(to: request.stderrURL)
            return 1
        }
        await assertError(.failed("screencapture exited with status 1: helper failed"), runner: runner)
        await assertAllRemoved(runner)
    }

    func testCompletePNGReturnsBeforeExitButRetainsGateAndFiles() async throws {
        let runner = FakeScreenCaptureRunner()
        let backend = makeBackend(runner: runner)
        let capture = Task { try await backend.captureRegion() }
        await waitUntil { await runner.calls.count == 1 }
        let calls = await runner.calls
        let request = try XCTUnwrap(calls.first)
        try Self.writePNG(to: request.output, dpi: 144)
        await runner.deliverPNG()
        let image = try await capture.value
        XCTAssertEqual(image.image.width, 20)
        XCTAssertEqual(image.pixelsPerPoint, 2, accuracy: 0.01)
        await assertError(.cancelled, backend: backend)
        XCTAssertTrue(FileManager.default.fileExists(atPath: request.output.path))
        await runner.finish()
        await waitUntil { !FileManager.default.fileExists(atPath: request.output.deletingLastPathComponent().path) }
        assertRemoved(request)
    }

    // Every backend dependency that could touch desktop state or TCC is fake, even on success.
    private func makeBackend(
        runner: FakeScreenCaptureRunner,
        hasPermission: @escaping @MainActor @Sendable () -> Bool = { true },
        requestPermission: @escaping @MainActor @Sendable () -> Bool = { XCTFail("Unexpected permission request"); return false },
        isControlHeld: @escaping @MainActor @Sendable () -> Bool = { false },
        clipboardChangeCount: @escaping @MainActor @Sendable () -> Int = { 0 },
        modifierReleaseTimeout: Duration = .seconds(1)
    ) -> NativeScreenCaptureBackend {
        NativeScreenCaptureBackend(
            runner: runner, hasPermission: hasPermission, requestPermission: requestPermission,
            isControlHeld: isControlHeld, clipboardChangeCount: clipboardChangeCount,
            modifierReleaseTimeout: modifierReleaseTimeout
        )
    }

    private func assertError(_ expected: RegionCaptureError, runner: FakeScreenCaptureRunner, hasPermission: Bool = true) async {
        var checks = 0
        await assertError(expected, backend: makeBackend(runner: runner, hasPermission: {
            checks += 1
            return hasPermission || checks == 1 // Simulate revocation after launch, not initial denial.
        }))
    }

    private func assertError(_ expected: RegionCaptureError, backend: NativeScreenCaptureBackend) async {
        do { _ = try await backend.captureRegion(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? RegionCaptureError, expected) }
    }

    private func assertCancelled(_ task: Task<CapturedRegion, any Error>) async {
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? RegionCaptureError, .cancelled) }
    }

    private func assertAllRemoved(_ runner: FakeScreenCaptureRunner) async {
        for call in await runner.calls { assertRemoved(call) }
    }

    private func assertRemoved(_ request: FakeScreenCaptureRunner.Request) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.stderrURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.output.deletingLastPathComponent().path))
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for fake process")
    }

    private nonisolated static func writePNG(to url: URL, dpi: Double? = nil) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = dpi.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

/// No subprocess, capture API, preflight, or UI is used by any test in this file.
private actor FakeScreenCaptureRunner: ScreenCaptureProcessRunning {
    struct Request: Sendable {
        let executableURL: URL
        let arguments: [String]
        let stderrURL: URL
        var output: URL { URL(fileURLWithPath: arguments.last!) }
    }
    private(set) var calls: [Request] = []
    private(set) var terminationRequested = false
    private let behavior: (@Sendable (Request) throws -> Int32)?
    private var continuation: CheckedContinuation<Int32, Never>?
    private var onPNGReady: (@Sendable () async -> Void)?

    init(behavior: (@Sendable (Request) throws -> Int32)? = nil) { self.behavior = behavior }

    func run(
        executableURL: URL, arguments: [String], stderrURL: URL, outputURL: URL,
        onPNGReady: @escaping @Sendable () async -> Void
    ) async throws -> Int32 {
        try Task.checkCancellation()
        let request = Request(executableURL: executableURL, arguments: arguments, stderrURL: stderrURL)
        calls.append(request)
        self.onPNGReady = onPNGReady
        if let behavior { return try behavior(request) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.terminate() }
        }
    }

    func deliverPNG() async { await onPNGReady?() }

    private func terminate() { terminationRequested = true }

    func finish() {
        continuation?.resume(returning: 0)
        continuation = nil
    }
}

@MainActor
private final class NativeCaptureTestEngine: TTSEngine {
    let id = "native-capture-test"
    let availableVoices: [Voice] = []
    let state: TTSEngineState = .stopped
    var onStateChange: ((TTSEngineState) -> Void)?
    func speak(text: String, options: SpeechOptions) { XCTFail("Cancelled capture must not speak") }
    func stop() {}
    func pause() {}
    func resume() {}
}

@MainActor
private final class NativeCaptureTestMuter: AudioMuting {
    func start(mode: AudioInterruptionMode) -> Bool { false }
    func stop() {}
}

@MainActor
private final class NativeCaptureControlState {
    var isHeld = true
    var polls = 0
}
