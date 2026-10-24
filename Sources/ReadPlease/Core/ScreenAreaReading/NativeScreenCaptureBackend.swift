// Adapted from TRex captureScreenInteractively (MIT) and BetterShot interactiveShot /
// validateCommandResult (BSD-3-Clause). See THIRD_PARTY_NOTICES.md for licences and pinned sources.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

@MainActor
final class NativeScreenCaptureBackend: RegionCapturing {
    private let runner: any ScreenCaptureProcessRunning
    private let hasPermission: @MainActor @Sendable () -> Bool
    private let requestPermission: @MainActor @Sendable () -> Bool
    private let isControlHeld: @MainActor @Sendable () -> Bool
    private let clipboardChangeCount: @MainActor @Sendable () -> Int
    private let modifierReleaseTimeout: Duration
    private var hasRequestedPermission = false
    private var isCapturing = false

    init(
        runner: any ScreenCaptureProcessRunning = NativeScreenCaptureProcessRunner(),
        hasPermission: @escaping @MainActor @Sendable () -> Bool = { ScreenRecordingPermission.isGranted() },
        requestPermission: @escaping @MainActor @Sendable () -> Bool = { CGRequestScreenCaptureAccess() },
        isControlHeld: @escaping @MainActor @Sendable () -> Bool = { NSEvent.modifierFlags.contains(.control) },
        clipboardChangeCount: @escaping @MainActor @Sendable () -> Int = { NSPasteboard.general.changeCount },
        modifierReleaseTimeout: Duration = .seconds(1)
    ) {
        self.runner = runner
        self.hasPermission = hasPermission
        self.requestPermission = requestPermission
        self.isControlHeld = isControlHeld
        self.clipboardChangeCount = clipboardChangeCount
        self.modifierReleaseTimeout = modifierReleaseTimeout
    }

    func captureRegion() async throws -> CapturedRegion {
        try Task.checkCancellation()
        // Stop clears the coordinator task before selector teardown completes. Re-press is silent.
        guard !isCapturing else { throw RegionCaptureError.cancelled }
        isCapturing = true
        do {
            guard hasPermission() else {
                // This method runs only for an explicit hotkey/menu action. Register the app and
                // show the system permission flow once per backend lifetime; never launch a doomed
                // selector. Even a synchronous grant requires a fresh invocation after this prompt.
                if !hasRequestedPermission {
                    hasRequestedPermission = true
                    _ = requestPermission()
                }
                throw RegionCaptureError.permissionNeeded
            }
            ScreenAreaTiming.current?.event("permission_preflight_done")
            let modifierStart = ContinuousClock.now
            let deadline = ContinuousClock.now.advanced(by: modifierReleaseTimeout)
            // Hotkeys fire on keyUp while Control can still be held. Avoid entering the native
            // selector until it is released; holding Control later still redirects to clipboard.
            while isControlHeld() {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw RegionCaptureError.failed("Release Control, then try Read Screen Area again.")
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            ScreenAreaTiming.current?.event("control_released", since: modifierStart)
            try Task.checkCancellation()
        } catch {
            isCapturing = false
            throw Self.captureError(error)
        }

        // Count only: never read or restore clipboard contents. Another app can change this count,
        // so a missing-file diagnostic describes a possible redirect rather than claiming proof.
        let clipboardBefore = clipboardChangeCount()
        let (images, delivery) = AsyncThrowingStream<CapturedRegion, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Deliberately unstructured: a complete PNG can reach OCR before Spotlight tagging exits.
        // This worker retains the backend gate and temp directory until the actual child exits.
        let worker = Task { @MainActor in
            defer { self.isCapturing = false }
            do {
                let image = try await Self.capture(
                    runner: runner, hasPermission: hasPermission,
                    clipboardChangeCount: clipboardChangeCount, clipboardBefore: clipboardBefore,
                    onImageReady: { delivery.yield($0) }
                )
                delivery.yield(image)
                delivery.finish()
            } catch {
                delivery.finish(throwing: Self.captureError(error))
            }
        }
        do {
            return try await withTaskCancellationHandler {
                var iterator = images.makeAsyncIterator()
                guard let image = try await iterator.next() else { throw RegionCaptureError.cancelled }
                try Task.checkCancellation()
                return image
            } onCancel: {
                worker.cancel()
            }
        } catch {
            worker.cancel()
            await worker.value
            throw Self.captureError(error)
        }
    }

    @concurrent
    private static func capture(
        runner: any ScreenCaptureProcessRunning,
        hasPermission: @escaping @MainActor @Sendable () -> Bool,
        clipboardChangeCount: @MainActor @Sendable () -> Int,
        clipboardBefore: Int,
        onImageReady: @escaping @Sendable (CapturedRegion) -> Void
    ) async throws -> CapturedRegion {
        try Task.checkCancellation()
        let files = FileManager.default
        let directory = files.temporaryDirectory.appending(path: "ReadPlease-capture-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? files.removeItem(at: directory) }
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let output = directory.appending(path: "region.png")
        let stderr = directory.appending(path: "stderr.txt")
        // -s disables Space's window-mode toggle; preserve DPI metadata (no -r).
        let status = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: ["-i", "-x", "-s", "-t", "png", output.path],
            stderrURL: stderr, outputURL: output,
            onPNGReady: {
                guard !Task.isCancelled, await hasPermission(), let image = try? loadImage(at: output) else { return }
                onImageReady(image)
            }
        )
        try Task.checkCancellation()
        // Check before interpreting any exit status/diagnostic, including permission errors.
        guard await hasPermission() else { throw RegionCaptureError.permissionNeeded }
        try Task.checkCancellation()
        let diagnostic = readDiagnostic(at: stderr)
        if status != 0 && (status != 1 || !diagnostic.isEmpty) {
            throw RegionCaptureError.failed("screencapture exited with status \(status)\(diagnostic.isEmpty ? "." : ": \(diagnostic)")")
        }
        guard files.fileExists(atPath: output.path) else {
            if await clipboardChangeCount() != clipboardBefore {
                throw RegionCaptureError.failed("Release Control while selecting. The capture may have gone to the clipboard.")
            }
            // Esc normally exits 0/1 with no file and no clipboard change.
            throw RegionCaptureError.cancelled
        }
        guard status == 0 else { throw RegionCaptureError.failed("screencapture exited with status \(status).") }
        return try loadImage(at: output)
    }

    private nonisolated static func captureError(_ error: any Error) -> RegionCaptureError {
        if error is CancellationError { return .cancelled }
        return error as? RegionCaptureError ?? .failed(error.localizedDescription)
    }

    private nonisolated static func loadImage(at output: URL) throws -> CapturedRegion {
        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw RegionCaptureError.failed("The captured PNG could not be read.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        // Assume PNG DPI = 72 points/inch × backing scale. Without a display ID, missing/invalid
        // DPI falls back to 1, never main-screen scale. OCR geometry remains in image pixels.
        let scale = dpi.isFinite && dpi > 0 ? dpi / 72 : 1
        return CapturedRegion(image: image, pixelsPerPoint: scale)
    }

    private nonisolated static func readDiagnostic(at url: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? file.close() }
        let data = (try? file.read(upToCount: 16_384)) ?? Data()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
