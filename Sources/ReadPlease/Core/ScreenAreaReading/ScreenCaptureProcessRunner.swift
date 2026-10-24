// Adapted from BetterShot ScreencaptureRunner, including PNG IEND detection (BSD-3-Clause).
// See THIRD_PARTY_NOTICES.md. Changes add cancellable teardown and file-backed stderr.
import Darwin
import Foundation

protocol ScreenCaptureProcessRunning: Sendable {
    /// Deliver a complete PNG early, but return only once the process and callback have finished.
    func run(
        executableURL: URL, arguments: [String], stderrURL: URL, outputURL: URL,
        onPNGReady: @escaping @Sendable () async -> Void
    ) async throws -> Int32
}

struct NativeScreenCaptureProcessRunner: ScreenCaptureProcessRunning {
    var terminationGracePeriod: Duration = .milliseconds(1_500)
    var onLaunch: @Sendable (Int32) -> Void = { _ in }

    @concurrent
    func run(
        executableURL: URL, arguments: [String], stderrURL: URL, outputURL: URL,
        onPNGReady: @escaping @Sendable () async -> Void
    ) async throws -> Int32 {
        try Task.checkCancellation()
        // File-backed stderr cannot fill a pipe and deadlock exit; the backend bounds its read.
        guard FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw RegionCaptureError.failed("Could not prepare capture diagnostics.")
        }
        let errors = try FileHandle(forWritingTo: stderrURL)
        defer { try? errors.close() }
        let session = ScreenCaptureProcessSession(terminationGracePeriod: terminationGracePeriod)
        let status = try await withTaskCancellationHandler {
            try await session.run(
                executableURL: executableURL, arguments: arguments, errors: errors,
                outputURL: outputURL, onPNGReady: onPNGReady, onLaunch: onLaunch
            )
        } onCancel: {
            Task { await session.cancel() }
        }
        try Task.checkCancellation()
        return status
    }

    // Adapted from BetterShot isCompletePNG: IEND is the final 12 bytes of a complete PNG.
    static func isCompletePNG(at url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(), size >= 12 else { return false }
        do {
            try file.seek(toOffset: size - 12)
            return try file.read(upToCount: 12) == Data([0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        } catch { return false }
    }
}

/// Launch/cancel are serialized off the main actor; the continuation resolves only on actual exit.
private actor ScreenCaptureProcessSession {
    private let terminationGracePeriod: Duration
    private var process: Process?
    private var cancelled = false
    private var exitStatus: Int32?
    private var exitWaiter: CheckedContinuation<Int32, Never>?
    private var escalation: Task<Void, Never>?

    init(terminationGracePeriod: Duration) { self.terminationGracePeriod = terminationGracePeriod }

    func run(
        executableURL: URL, arguments: [String], errors: FileHandle, outputURL: URL,
        onPNGReady: @escaping @Sendable () async -> Void,
        onLaunch: @Sendable (Int32) -> Void
    ) async throws -> Int32 {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let child = Process()
        child.executableURL = executableURL
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = errors
        child.terminationHandler = { completed in
            let status = completed.terminationStatus
            Task { await self.didExit(status) }
        }
        process = child
        do {
            try child.run()
        } catch {
            child.terminationHandler = nil
            process = nil
            throw error
        }
        ScreenAreaTiming.current?.event("native_process_launched", detail: "selector_visibility=not_observable")
        onLaunch(child.processIdentifier)
        let poller = Task {
            while !Task.isCancelled && !cancelled && exitStatus == nil {
                if NativeScreenCaptureProcessRunner.isCompletePNG(at: outputURL) {
                    ScreenAreaTiming.current?.event("png_complete")
                    await onPNGReady()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(25)) }
                catch { return }
            }
        }
        let status = await withCheckedContinuation { continuation in
            if let exitStatus { continuation.resume(returning: exitStatus) }
            else { exitWaiter = continuation }
        }
        ScreenAreaTiming.current?.event("native_process_exited", detail: "status=\(status)")
        poller.cancel()
        await poller.value // No callback may touch output after the backend removes its directory.
        child.terminationHandler = nil
        process = nil
        return status
    }

    private func didExit(_ status: Int32) {
        exitStatus = status
        escalation?.cancel()
        escalation = nil
        exitWaiter?.resume(returning: status)
        exitWaiter = nil
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        guard let process, exitStatus == nil, process.isRunning else { return }
        process.terminate()
        escalation = Task {
            do { try await Task.sleep(for: terminationGracePeriod) }
            catch { return }
            // Actor state/Process.isRunning prevent signalling a reaped/reused PID.
            guard exitStatus == nil, process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
