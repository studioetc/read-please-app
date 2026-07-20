import AppKit
import XCTest
@testable import ReadPlease

@MainActor
final class TextSelectionServiceTests: XCTestCase {
    func testClipboardTextRequiresOwnershipChange() {
        XCTAssertNil(
            TextSelectionService.validatedClipboardText(
                changeCount: 10,
                captureChangeCount: 10,
                text: "Old clipboard contents"
            )
        )
    }

    func testClipboardCaptureMarkerIsNotExposedAsPasteableText() {
        let pasteboard = NSPasteboard(name: .init("ReadPleaseTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }

        TextSelectionService.prepareClipboardForCapture(pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertNotNil(
            pasteboard.data(
                forType: .init("org.nspasteboard.TransientType")
            )
        )
    }

    func testChangedClipboardTextIsAccepted() {
        XCTAssertEqual(
            TextSelectionService.validatedClipboardText(
                changeCount: 11,
                captureChangeCount: 10,
                text: "Current selection"
            ),
            "Current selection"
        )
    }
}
