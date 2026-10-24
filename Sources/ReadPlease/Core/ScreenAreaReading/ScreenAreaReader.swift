import Foundation

@MainActor
final class ScreenAreaReader {
    /// The native-selector or frozen-overlay branch installs its backend here at app composition.
    var captureBackend: (any RegionCapturing)?
    private let recognize: @Sendable (CapturedRegion) async throws -> [OCRLine]

    init(
        captureBackend: (any RegionCapturing)? = nil,
        recognize: @escaping @Sendable (CapturedRegion) async throws -> [OCRLine] = {
            try await TextRecognizer().recognize($0)
        }
    ) {
        self.captureBackend = captureBackend
        self.recognize = recognize
    }

    func readText() async throws -> String {
        try Task.checkCancellation()
        guard let captureBackend else { throw ScreenAreaReadError.notAvailableYet }
        let captureStart = ContinuousClock.now
        ScreenAreaTiming.current?.event("capture_started")
        let region = try await captureBackend.captureRegion()
        ScreenAreaTiming.current?.event("image_returned", since: captureStart,
                                        detail: "width=\(region.image.width) height=\(region.image.height)")
        try Task.checkCancellation()
        let ocrStart = ContinuousClock.now
        let lines = try await recognize(region)
        ScreenAreaTiming.current?.event("ocr_done", since: ocrStart, detail: "lines=\(lines.count)")
        try Task.checkCancellation()
        let formatStart = ContinuousClock.now
        ScreenAreaTiming.current?.recognizedLines(lines)
        let text = SpeechTextFormatter.format(OCRLayout.readingOrderRows(lines))
        ScreenAreaTiming.current?.event("formatted", since: formatStart, detail: "chars=\(text.count)")
        ScreenAreaTiming.current?.recognizedText(text)
        guard !text.isEmpty else { throw ScreenAreaReadError.noTextFound }
        return text
    }
}

enum ScreenAreaReadError: Error {
    case notAvailableYet
    case noTextFound
}

enum ScreenAreaReadOutcome: Equatable {
    case notAvailableYet
    case noTextFound
    case permissionNeeded
    case failed(String)

    var message: String {
        switch self {
        case .notAvailableYet:
            "Read Screen Area is not available yet. It is coming in a later update."
        case .noTextFound:
            "No text found in the selected area. Try a tighter selection or larger text."
        case .permissionNeeded:
            "Screen Recording permission is needed to read text from other apps. After granting it, you may need to quit and reopen ReadPlease."
        case .failed(let detail):
            "Couldn't read the screen area: \(detail)"
        }
    }
}
