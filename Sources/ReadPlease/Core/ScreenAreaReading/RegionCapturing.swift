import CoreGraphics

/// Capture backends own selection UI and permission handling. They must clean up on cancellation
/// and reject reentry until a cancelled selector has fully closed.
@MainActor
protocol RegionCapturing {
    func captureRegion() async throws -> CapturedRegion
}

struct CapturedRegion: Sendable {
    let image: CGImage
    /// Source pixels per selection point; OCR geometry always uses image pixels.
    let pixelsPerPoint: CGFloat

    init(image: CGImage, pixelsPerPoint: CGFloat = 1) {
        self.image = image
        self.pixelsPerPoint = pixelsPerPoint
    }
}

enum RegionCaptureError: Error, Equatable {
    case cancelled
    case permissionNeeded
    case failed(String)
}
