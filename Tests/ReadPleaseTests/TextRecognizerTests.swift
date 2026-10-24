import CoreGraphics
import CoreText
import Foundation
import Vision
import XCTest
@testable import ReadPlease

final class TextRecognizerTests: XCTestCase {
    func testRecognizesCoreTextImageWithoutScreenCapture() async throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1100, height: 220, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1100, height: 220))
        let text = NSAttributedString(string: "The quick brown fox reads aloud", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 40, y: 170)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let region = CapturedRegion(image: try XCTUnwrap(context.makeImage()), pixelsPerPoint: 2)
        let lines: [OCRLine]
        do {
            lines = try await TextRecognizer().recognize(region)
        } catch {
            guard Self.isOCRUnavailable(error) else { throw error }
            throw XCTSkip("Vision OCR model or compute device is unavailable on this host: \(error.localizedDescription)")
        }
        XCTAssertTrue(lines.map(\.text).joined(separator: " ").lowercased().contains("the quick brown fox reads aloud"))
        let first = try XCTUnwrap(lines.first)
        XCTAssertGreaterThan(first.confidence, 0)
        XCTAssertGreaterThan(first.box.width, 0)
        XCTAssertGreaterThan(first.textHeight, 0)
        XCTAssertGreaterThanOrEqual(first.box.minX, 0)
        XCTAssertGreaterThanOrEqual(first.box.minY, 0)
        XCTAssertLessThan(first.box.minY, CGFloat(region.image.height) / 3, "Text drawn near the top must use top-left image coordinates.")
        XCTAssertLessThanOrEqual(first.box.maxX, CGFloat(region.image.width))
        XCTAssertLessThanOrEqual(first.box.maxY, CGFloat(region.image.height))
    }

    func testOnlyKnownUnavailableErrorsPermitSkippingOCR() {
        XCTAssertTrue(Self.isOCRUnavailable(VisionError.dataUnavailable("OCR model missing")))
        XCTAssertTrue(Self.isOCRUnavailable(VisionError.unsupportedComputeDevice("Device unavailable")))
        XCTAssertFalse(Self.isOCRUnavailable(VisionError.invalidArgument("Invalid request")))
        XCTAssertFalse(Self.isOCRUnavailable(VisionError.operationFailed("Unexpected OCR failure")))
        XCTAssertFalse(Self.isOCRUnavailable(CancellationError()))
        XCTAssertFalse(Self.isOCRUnavailable(NSError(domain: "Unknown", code: 1)))
    }

    private static func isOCRUnavailable(_ error: any Error) -> Bool {
        switch error {
        case VisionError.dataUnavailable, VisionError.unsupportedComputeDevice: true
        default: false
        }
    }
}
