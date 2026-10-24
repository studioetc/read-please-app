import Darwin
import Foundation
import XCTest
@testable import ReadPlease

/// Exercises Foundation Process only with harmless, explicitly selected executables. No capture,
/// desktop state, permission/preflight call or app launch is involved.
@MainActor
final class NativeScreenCaptureProcessRunnerTests: XCTestCase {
    func testRealRunnerCollectsStderrAndNonzeroStatus() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let errors = directory.appending(path: "stderr.txt")
        let status = try await NativeScreenCaptureProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo x >&2; exit 1"],
            stderrURL: errors, outputURL: directory.appending(path: "unused.png"),
            onPNGReady: { XCTFail("No PNG should exist") }
        )
        XCTAssertEqual(status, 1)
        XCTAssertEqual(try String(contentsOf: errors, encoding: .utf8), "x\n")
    }

    func testRealSleepCancellationWaitsForActualExit() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launched = LaunchProbe()
        let runner = NativeScreenCaptureProcessRunner(onLaunch: { pid in Task { await launched.record(pid) } })
        let task = Task {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                stderrURL: directory.appending(path: "stderr.txt"), outputURL: directory.appending(path: "unused.png"),
                onPNGReady: { XCTFail("No PNG should exist") }
            )
        }
        await waitUntil { await launched.pid != nil }
        let pid = await launched.pid
        let started = ContinuousClock.now
        task.cancel()
        await assertCancelled(task)
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
        assertExited(try XCTUnwrap(pid))
    }

    func testSIGTERMIgnoringChildIsKilledAfterGracePeriod() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appending(path: "ready")
        let launched = LaunchProbe()
        let runner = NativeScreenCaptureProcessRunner(
            terminationGracePeriod: .milliseconds(150), onLaunch: { pid in Task { await launched.record(pid) } }
        )
        let task = Task {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; printf ready > \"$1\"; exec /bin/sleep 30", "--", ready.path],
                stderrURL: directory.appending(path: "stderr.txt"), outputURL: directory.appending(path: "unused.png"),
                onPNGReady: { XCTFail("No PNG should exist") }
            )
        }
        await waitUntil { FileManager.default.fileExists(atPath: ready.path) }
        await waitUntil { await launched.pid != nil }
        let pid = await launched.pid
        let started = ContinuousClock.now
        task.cancel()
        await assertCancelled(task)
        let elapsed = started.duration(to: .now)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        XCTAssertLessThan(elapsed, .seconds(5))
        assertExited(try XCTUnwrap(pid))
    }

    func testRealRunnerDeliversIENDWhileProcessIsStillRunning() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "output.png")
        let launched = LaunchProbe()
        let ready = LaunchProbe()
        let runner = NativeScreenCaptureProcessRunner(onLaunch: { pid in Task { await launched.record(pid) } })
        let task = Task {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                stderrURL: directory.appending(path: "stderr.txt"), outputURL: output,
                onPNGReady: { await ready.record(1) }
            )
        }
        await waitUntil { await launched.pid != nil }
        // A truncated footer is not ready. Finish it while the harmless child keeps running.
        let footer = Data([0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        try footer.prefix(8).write(to: output)
        XCTAssertFalse(NativeScreenCaptureProcessRunner.isCompletePNG(at: output))
        try footer.write(to: output)
        await waitUntil { await ready.pid != nil }
        let pid = await launched.pid
        XCTAssertEqual(kill(try XCTUnwrap(pid), 0), 0)
        task.cancel()
        await assertCancelled(task)
        assertExited(try XCTUnwrap(pid))
    }

    func testIENDDetectorRejectsMissingShortAndWrongTrailer() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "output.png")
        XCTAssertFalse(NativeScreenCaptureProcessRunner.isCompletePNG(at: output))
        try Data([0, 1]).write(to: output)
        XCTAssertFalse(NativeScreenCaptureProcessRunner.isCompletePNG(at: output))
        try Data(repeating: 0, count: 20).write(to: output)
        XCTAssertFalse(NativeScreenCaptureProcessRunner.isCompletePNG(at: output))
    }

    func testRealRunnerLaunchFailureReturnsWithoutPollingForever() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await NativeScreenCaptureProcessRunner().run(
                executableURL: directory.appending(path: "nonexistent"), arguments: [],
                stderrURL: directory.appending(path: "stderr.txt"), outputURL: directory.appending(path: "unused.png"),
                onPNGReady: { XCTFail("No PNG should exist") }
            )
            XCTFail("Expected launch failure")
        } catch { XCTAssertFalse(error is CancellationError) }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ReadPlease-runner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func assertCancelled(_ task: Task<Int32, any Error>) async {
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func assertExited(_ pid: Int32) {
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for harmless child")
    }
}

private actor LaunchProbe {
    private(set) var pid: Int32?
    func record(_ pid: Int32) { self.pid = pid }
}
