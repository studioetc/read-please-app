import Testing
@testable import ReadPlease

@Suite struct SystemTTSEngineTests {
    @Test func testLineAndParagraphSeparatorsBecomeNewlines() {
        let notesText = "Small apps\u{2028}Aviation - CDO and CCO performance\u{2029}Next"
        #expect(
            SystemTTSEngine.normalizingLineSeparators(notesText)
                == "Small apps\nAviation - CDO and CCO performance\nNext"
        )
    }

    @Test func testTextWithoutSeparatorsIsUnchanged() {
        let text = "Line one\nLine two"
        #expect(SystemTTSEngine.normalizingLineSeparators(text) == text)
    }
}
