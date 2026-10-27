import CoreGraphics
import CoreText
import Foundation
import Vision
import Testing
@testable import ReadPlease

@Suite final class TextRecognizerTests {
    @Test func testRecognizesCoreTextImageWithoutScreenCapture() async throws {
        let context = try #require(CGContext(
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
        let region = CapturedRegion(image: try #require(context.makeImage()), pixelsPerPoint: 2)
        let lines: [OCRLine]
        do {
            lines = try await TextRecognizer().recognize(region)
        } catch {
            guard Self.isOCRUnavailable(error) else { throw error }
            // Swift Testing on Swift 6.2 has no runtime skip; treat an unavailable OCR host as a pass.
            print("Skipping: Vision OCR model or compute device is unavailable on this host: \(error.localizedDescription)")
            return
        }
        #expect(lines.map(\.text).joined(separator: " ").lowercased().contains("the quick brown fox reads aloud"))
        let first = try #require(lines.first)
        #expect(first.confidence > 0)
        #expect(first.box.width > 0)
        #expect(first.textHeight > 0)
        #expect(first.box.minX >= 0)
        #expect(first.box.minY >= 0)
        #expect(first.box.minY < (CGFloat(region.image.height) / 3), "Text drawn near the top must use top-left image coordinates.")
        #expect(first.box.maxX <= CGFloat(region.image.width))
        #expect(first.box.maxY <= CGFloat(region.image.height))
    }

    @Test func testOnlyKnownUnavailableErrorsPermitSkippingOCR() {
        #expect(Self.isOCRUnavailable(VisionError.dataUnavailable("OCR model missing")))
        #expect(Self.isOCRUnavailable(VisionError.unsupportedComputeDevice("Device unavailable")))
        #expect(!(Self.isOCRUnavailable(VisionError.invalidArgument("Invalid request"))))
        #expect(!(Self.isOCRUnavailable(VisionError.operationFailed("Unexpected OCR failure"))))
        #expect(!(Self.isOCRUnavailable(CancellationError())))
        #expect(!(Self.isOCRUnavailable(NSError(domain: "Unknown", code: 1))))
    }

    private static func isOCRUnavailable(_ error: any Error) -> Bool {
        switch error {
        case VisionError.dataUnavailable, VisionError.unsupportedComputeDevice: true
        default: false
        }
    }
}
