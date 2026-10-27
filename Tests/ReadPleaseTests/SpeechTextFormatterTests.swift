import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class SpeechTextFormatterTests {
    @Test func testWrappedLinesJoinWithSpaces() {
        #expect(format(["A visually wrapped", "paragraph continues."]) == "A visually wrapped paragraph continues.")
    }

    @Test func testParagraphGapsAndIndentationStaySeparate() {
        #expect((SpeechTextFormatter.format([
            [line("First paragraph.", y: 0)], [line("Second paragraph.", y: 45)],
            [line("Indented paragraph.", x: 45, y: 69)],
        ])) == "First paragraph.\n\nSecond paragraph.\n\nIndented paragraph.")
    }

    @Test func testColumnTransitionAndHeadingStaySeparate() {
        #expect((SpeechTextFormatter.format([
            [line("Left column", y: 0)], [line("continues", y: 24)],
            [line("Right column", x: 300, y: 0)],
        ])) == "Left column continues\n\nRight column")
        #expect((SpeechTextFormatter.format([
            [line("Heading", y: 0, height: 32)], [line("Body", y: 36, height: 16)],
        ])) == "Heading\n\nBody")
    }

    @Test func testLowercaseWrapRetainsRecognizedHyphen() {
        #expect(format(["An exam-", "ple appears."]) == "An exam-ple appears.")
        #expect(format(["inter-", "national news"]) == "inter-national news")
    }

    @Test func testScreenPhraseKeepsSpacedDashAcrossWrap() {
        for dash in ["—", "–", "-"] {
            #expect(format(["Hello world " + dash, "typed in background"]) == ("Hello world " + dash + " typed in background"))
            #expect(format(["Hello world " + dash + " typed in background"]) == ("Hello world " + dash + " typed in background"))
        }
    }

    @Test func testUnicodeDashAtWrapKeepsPauseAndDoesNotDehyphenate() {
        for dash in ["—", "–"] {
            #expect(format(["Hello world" + dash, "typed in background"]) == ("Hello world" + dash + " typed in background"))
        }
        #expect(format(["Hello world\t-", "typed in background"]) == "Hello world\t- typed in background")
    }

    @Test func testCompoundsNumbersURLsAndCodeLikeTextKeepHyphens() {
        #expect(format(["well-known facts", "stay intact"]) == "well-known facts stay intact")
        #expect(format(["well-", "known facts"]) == "well-known facts")
        #expect(format(["pages 10-", "20"]) == "pages 10-20")
        #expect(format(["https://example.com/exam-", "ple"]) == "https://example.com/exam-ple")
        #expect(format(["let identifier = exam-", "ple"]) == "let identifier = exam-ple")
        #expect(format(["some_identifier-", "part"]) == "some_identifier-part")
        #expect(format(["API-", "Driven"]) == "API-Driven")
    }

    @Test func testListItemsRetainSingleRowBreaks() {
        #expect(format(["Introduction", "• First item", "• Second item"]) == "Introduction\n• First item\n• Second item")
    }

    @Test func testSameRowFragmentsJoinAndInlinePunctuationHasNoExtraSpace() {
        #expect((SpeechTextFormatter.format([[line("Hello", y: 0), line("world", x: 100, y: 0)]])) == "Hello world")
        #expect(format(["Hello", ", world"]) == "Hello, world")
    }

    @Test func testCJKWrapsDoNotGainSpaces() {
        #expect(format(["日本語", "文章"]) == "日本語文章")
    }

    @Test func testFirstLineIndentAndHangingListContinuationReflow() {
        #expect((SpeechTextFormatter.format([
            [line("An indented start", x: 40, y: 0)], [line("continues here.", y: 24)],
        ])) == "An indented start continues here.")
        #expect((SpeechTextFormatter.format([
            [line("• A wrapped bullet", y: 0)], [line("continues here.", x: 40, y: 24)],
        ])) == "• A wrapped bullet continues here.")
    }

    @Test func testRightAlignedRTLWrapReflowsDespiteDifferentLeftEdges() {
        let first = OCRLine(text: "שלום עולם", box: CGRect(x: 0, y: 0, width: 250, height: 20))
        let next = OCRLine(text: "שלום", box: CGRect(x: 80, y: 24, width: 170, height: 20))
        #expect(SpeechTextFormatter.format([[first], [next]]) == "שלום עולם שלום")
    }

    @Test func testProsePunctuationDoesNotImplyCode() {
        #expect(format(["This is prose;", "it should reflow."]) == "This is prose; it should reflow.")
        #expect(format(["The number is < 10", "in this example."]) == "The number is < 10 in this example.")
    }

    @Test func testCodeSyntaxAndBracesDoNotAddSpeechFormatting() {
        #expect(format(["let value = {", "item_name; }"]) == "let value = { item_name; }")
        #expect(format(["A label:", "the following words"]) == "A label: the following words")
    }

    @Test func testDenseTableRowsKeepSingleRowBreaks() {
        let grid = [["Item", "Qty", "Price"], ["Pens", "12", "3.50"], ["Paper", "5", "8.00"]]
        let lines = grid.enumerated().flatMap { row, cells in
            cells.enumerated().map { column, text in
                OCRLine(text: text, box: CGRect(x: column * 180, y: row * 24, width: 60, height: 18))
            }
        }
        #expect(OCRLayout.isTable(lines))
        let rows = OCRLayout.readingOrderRows(lines.reversed())
        #expect(SpeechTextFormatter.format(rows) == "Item Qty Price\nPens 12 3.50\nPaper 5 8.00")
    }

    @Test func testOneEmFirstLineIndentStartsANewParagraph() {
        #expect((SpeechTextFormatter.format([
            [line("Previous paragraph.", y: 0)],
            [line("New paragraph", x: 20, y: 24)],
            [line("continues here.", y: 48)],
        ])) == "Previous paragraph.\n\nNew paragraph continues here.")
    }

    @Test func testRecognizedHyphensAreNeverDictionaryCorrections() {
        #expect(format(["decision-", "making"]) == "decision-making")
        #expect(format(["exam-", "ple"]) == "exam-ple")
        #expect(format(["novel-", "word"]) == "novel-word")
    }

    @Test func testShortBodySizedLineDoesNotInventAHeadingPause() {
        let rows = [
            [OCRLine(text: "Introduction", box: CGRect(x: 0, y: 0, width: 100, height: 20))],
            [OCRLine(text: "The body starts here and wraps", box: CGRect(x: 0, y: 24, width: 400, height: 20))],
            [OCRLine(text: "onto this final line.", box: CGRect(x: 0, y: 48, width: 200, height: 20))],
        ]
        #expect(SpeechTextFormatter.format(rows) == "Introduction The body starts here and wraps onto this final line.")
    }

    @Test func testShortPunctuatedLineDoesNotInventAParagraph() {
        for ending in [".", ":", "?", "!"] {
            let rows = [
                [OCRLine(text: "A full width line of text", box: CGRect(x: 0, y: 0, width: 400, height: 20))],
                [OCRLine(text: "ends here" + ending, box: CGRect(x: 0, y: 24, width: 100, height: 20))],
                [OCRLine(text: "The next paragraph starts immediately.", box: CGRect(x: 0, y: 48, width: 400, height: 20))],
            ]
            #expect(SpeechTextFormatter.format(rows) == ("A full width line of text ends here" + ending + " The next paragraph starts immediately."))
        }
    }

    @Test func testShortLineUsesItsOwnColumnWidth() {
        var lines: [OCRLine] = []
        for index in 0..<3 {
            lines.append(OCRLine(text: "Left line", box: CGRect(x: 0, y: index * 24, width: 180, height: 20)))
            lines.append(OCRLine(text: "A much wider right column", box: CGRect(x: 240, y: index * 24, width: 300, height: 20)))
        }
        #expect((SpeechTextFormatter.format(OCRLayout.readingOrderRows(lines))) == "Left line Left line Left line\n\nA much wider right column A much wider right column A much wider right column")
    }

    @Test func testEmptyInput() {
        #expect(SpeechTextFormatter.format([]) == "")
        #expect(format(["   ", "\n"]) == "")
    }

    private func format(_ texts: [String]) -> String {
        SpeechTextFormatter.format(texts.enumerated().map { [line($0.element, y: CGFloat($0.offset * 24))] })
    }

    private func line(_ text: String, x: CGFloat = 0, y: CGFloat, height: CGFloat = 20) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: x, y: y, width: 250, height: height))
    }
}
