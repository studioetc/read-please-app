import Foundation
import XCTest
@testable import ReadPlease

@MainActor
final class SpeechTextFormatterTests: XCTestCase {
    func testWrappedLinesJoinWithSpaces() {
        XCTAssertEqual(format(["A visually wrapped", "paragraph continues."]), "A visually wrapped paragraph continues.")
    }

    func testParagraphGapsAndIndentationStaySeparate() {
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("First paragraph.", y: 0)], [line("Second paragraph.", y: 45)],
            [line("Indented paragraph.", x: 45, y: 69)],
        ]), "First paragraph.\n\nSecond paragraph.\n\nIndented paragraph.")
    }

    func testColumnTransitionAndHeadingStaySeparate() {
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("Left column", y: 0)], [line("continues", y: 24)],
            [line("Right column", x: 300, y: 0)],
        ]), "Left column continues\n\nRight column")
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("Heading", y: 0, height: 32)], [line("Body", y: 36, height: 16)],
        ]), "Heading\n\nBody")
    }

    func testLowercaseWrapRetainsRecognizedHyphen() {
        XCTAssertEqual(format(["An exam-", "ple appears."]), "An exam-ple appears.")
        XCTAssertEqual(format(["inter-", "national news"]), "inter-national news")
    }

    func testScreenPhraseKeepsSpacedDashAcrossWrap() {
        for dash in ["—", "–", "-"] {
            XCTAssertEqual(format(["Hello world " + dash, "typed in background"]),
                           "Hello world " + dash + " typed in background")
            XCTAssertEqual(format(["Hello world " + dash + " typed in background"]),
                           "Hello world " + dash + " typed in background")
        }
    }

    func testUnicodeDashAtWrapKeepsPauseAndDoesNotDehyphenate() {
        for dash in ["—", "–"] {
            XCTAssertEqual(format(["Hello world" + dash, "typed in background"]),
                           "Hello world" + dash + " typed in background")
        }
        XCTAssertEqual(format(["Hello world\t-", "typed in background"]),
                       "Hello world\t- typed in background")
    }

    func testCompoundsNumbersURLsAndCodeLikeTextKeepHyphens() {
        XCTAssertEqual(format(["well-known facts", "stay intact"]), "well-known facts stay intact")
        XCTAssertEqual(format(["well-", "known facts"]), "well-known facts")
        XCTAssertEqual(format(["pages 10-", "20"]), "pages 10-20")
        XCTAssertEqual(format(["https://example.com/exam-", "ple"]), "https://example.com/exam-ple")
        XCTAssertEqual(format(["let identifier = exam-", "ple"]), "let identifier = exam-ple")
        XCTAssertEqual(format(["some_identifier-", "part"]), "some_identifier-part")
        XCTAssertEqual(format(["API-", "Driven"]), "API-Driven")
    }

    func testListItemsRetainSingleRowBreaks() {
        XCTAssertEqual(format(["Introduction", "• First item", "• Second item"]),
                       "Introduction\n• First item\n• Second item")
    }

    func testSameRowFragmentsJoinAndInlinePunctuationHasNoExtraSpace() {
        XCTAssertEqual(SpeechTextFormatter.format([[line("Hello", y: 0), line("world", x: 100, y: 0)]]), "Hello world")
        XCTAssertEqual(format(["Hello", ", world"]), "Hello, world")
    }

    func testCJKWrapsDoNotGainSpaces() {
        XCTAssertEqual(format(["日本語", "文章"]), "日本語文章")
    }

    func testFirstLineIndentAndHangingListContinuationReflow() {
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("An indented start", x: 40, y: 0)], [line("continues here.", y: 24)],
        ]), "An indented start continues here.")
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("• A wrapped bullet", y: 0)], [line("continues here.", x: 40, y: 24)],
        ]), "• A wrapped bullet continues here.")
    }

    func testRightAlignedRTLWrapReflowsDespiteDifferentLeftEdges() {
        let first = OCRLine(text: "שלום עולם", box: CGRect(x: 0, y: 0, width: 250, height: 20))
        let next = OCRLine(text: "שלום", box: CGRect(x: 80, y: 24, width: 170, height: 20))
        XCTAssertEqual(SpeechTextFormatter.format([[first], [next]]), "שלום עולם שלום")
    }

    func testProsePunctuationDoesNotImplyCode() {
        XCTAssertEqual(format(["This is prose;", "it should reflow."]), "This is prose; it should reflow.")
        XCTAssertEqual(format(["The number is < 10", "in this example."]), "The number is < 10 in this example.")
    }

    func testCodeSyntaxAndBracesDoNotAddSpeechFormatting() {
        XCTAssertEqual(format(["let value = {", "item_name; }"]), "let value = { item_name; }")
        XCTAssertEqual(format(["A label:", "the following words"]), "A label: the following words")
    }

    func testDenseTableRowsKeepSingleRowBreaks() {
        let grid = [["Item", "Qty", "Price"], ["Pens", "12", "3.50"], ["Paper", "5", "8.00"]]
        let lines = grid.enumerated().flatMap { row, cells in
            cells.enumerated().map { column, text in
                OCRLine(text: text, box: CGRect(x: column * 180, y: row * 24, width: 60, height: 18))
            }
        }
        XCTAssertTrue(OCRLayout.isTable(lines))
        let rows = OCRLayout.readingOrderRows(lines.reversed())
        XCTAssertEqual(SpeechTextFormatter.format(rows), "Item Qty Price\nPens 12 3.50\nPaper 5 8.00")
    }

    func testOneEmFirstLineIndentStartsANewParagraph() {
        XCTAssertEqual(SpeechTextFormatter.format([
            [line("Previous paragraph.", y: 0)],
            [line("New paragraph", x: 20, y: 24)],
            [line("continues here.", y: 48)],
        ]), "Previous paragraph.\n\nNew paragraph continues here.")
    }

    func testRecognizedHyphensAreNeverDictionaryCorrections() {
        XCTAssertEqual(format(["decision-", "making"]), "decision-making")
        XCTAssertEqual(format(["exam-", "ple"]), "exam-ple")
        XCTAssertEqual(format(["novel-", "word"]), "novel-word")
    }

    func testShortBodySizedLineDoesNotInventAHeadingPause() {
        let rows = [
            [OCRLine(text: "Introduction", box: CGRect(x: 0, y: 0, width: 100, height: 20))],
            [OCRLine(text: "The body starts here and wraps", box: CGRect(x: 0, y: 24, width: 400, height: 20))],
            [OCRLine(text: "onto this final line.", box: CGRect(x: 0, y: 48, width: 200, height: 20))],
        ]
        XCTAssertEqual(SpeechTextFormatter.format(rows), "Introduction The body starts here and wraps onto this final line.")
    }

    func testShortPunctuatedLineDoesNotInventAParagraph() {
        for ending in [".", ":", "?", "!"] {
            let rows = [
                [OCRLine(text: "A full width line of text", box: CGRect(x: 0, y: 0, width: 400, height: 20))],
                [OCRLine(text: "ends here" + ending, box: CGRect(x: 0, y: 24, width: 100, height: 20))],
                [OCRLine(text: "The next paragraph starts immediately.", box: CGRect(x: 0, y: 48, width: 400, height: 20))],
            ]
            XCTAssertEqual(SpeechTextFormatter.format(rows), "A full width line of text ends here" + ending + " The next paragraph starts immediately.")
        }
    }

    func testShortLineUsesItsOwnColumnWidth() {
        var lines: [OCRLine] = []
        for index in 0..<3 {
            lines.append(OCRLine(text: "Left line", box: CGRect(x: 0, y: index * 24, width: 180, height: 20)))
            lines.append(OCRLine(text: "A much wider right column", box: CGRect(x: 240, y: index * 24, width: 300, height: 20)))
        }
        XCTAssertEqual(SpeechTextFormatter.format(OCRLayout.readingOrderRows(lines)),
                       "Left line Left line Left line\n\nA much wider right column A much wider right column A much wider right column")
    }

    func testEmptyInput() {
        XCTAssertEqual(SpeechTextFormatter.format([]), "")
        XCTAssertEqual(format(["   ", "\n"]), "")
    }

    private func format(_ texts: [String]) -> String {
        SpeechTextFormatter.format(texts.enumerated().map { [line($0.element, y: CGFloat($0.offset * 24))] })
    }

    private func line(_ text: String, x: CGFloat = 0, y: CGFloat, height: CGFloat = 20) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: x, y: y, width: 250, height: height))
    }
}
