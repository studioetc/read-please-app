import AppKit
import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class TextSelectionServiceTests {
    @Test func testClipboardTextRequiresOwnershipChange() {
        #expect(TextSelectionService.validatedClipboardText(
                changeCount: 10,
                captureChangeCount: 10,
                text: "Old clipboard contents"
            ) == nil)
    }

    @Test func testClipboardCaptureMarkerIsNotExposedAsPasteableText() {
        let pasteboard = NSPasteboard(name: .init("ReadPleaseTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }

        TextSelectionService.prepareClipboardForCapture(pasteboard)

        #expect(pasteboard.string(forType: .string) == nil)
        #expect((pasteboard.data(
                forType: .init("org.nspasteboard.TransientType")
            )) != nil)
    }

    @Test func testChangedClipboardTextIsAccepted() {
        #expect(TextSelectionService.validatedClipboardText(
                changeCount: 11,
                captureChangeCount: 10,
                text: "Current selection"
            ) == "Current selection")
    }
}
