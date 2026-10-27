import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class SelectionParityTests {
    @Test func testOriginalPreview() { assertParity(0) }
    @Test func testOriginalSafari() { assertParity(1) }
    @Test func testArticle() { assertParity(2) }
    @Test func testPunctuation() { assertParity(3) }
    @Test func testList() { assertParity(4) }
    @Test func testNumbers() { assertParity(5) }
    @Test func testHyphenation() { assertParity(6) }

    private func assertParity(_ index: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let fixture = SelectionParityFixtures.corpus[index]
        #expect(
            SpeechTextFormatter.format(OCRLayout.readingOrderRows(fixture.lines)) == fixture.expectedWithVisionGlyphs,
            Comment(rawValue: fixture.name),
            sourceLocation: sourceLocation
        )
    }
}
