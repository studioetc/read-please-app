import XCTest
@testable import ReadPlease

@MainActor
final class SelectionParityTests: XCTestCase {
    func testOriginalPreview() { assertParity(0) }
    func testOriginalSafari() { assertParity(1) }
    func testArticle() { assertParity(2) }
    func testPunctuation() { assertParity(3) }
    func testList() { assertParity(4) }
    func testNumbers() { assertParity(5) }
    func testHyphenation() { assertParity(6) }

    private func assertParity(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let fixture = SelectionParityFixtures.corpus[index]
        XCTAssertEqual(SpeechTextFormatter.format(OCRLayout.readingOrderRows(fixture.lines)),
                       fixture.expectedWithVisionGlyphs, fixture.name, file: file, line: line)
    }
}
