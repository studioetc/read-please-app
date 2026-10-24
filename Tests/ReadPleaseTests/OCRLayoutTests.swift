// Adapted from Shotnix OCRLayoutTests (MIT). See THIRD_PARTY_NOTICES.md.
// MIT License
//
// Copyright (c) 2025 Shotnix Contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import XCTest
@testable import ReadPlease

final class OCRLayoutTests: XCTestCase {
    func testTwoColumnsReadColumnByColumn() {
        var lines: [OCRLine] = []
        for (index, y) in stride(from: 100, to: 400, by: 40).enumerated() {
            lines.append(line("Left \(index)", x: 20, y: CGFloat(y), width: 230))
            lines.append(line("Right \(index)", x: 320, y: CGFloat(y), width: 230))
        }
        let text = OCRLayout.readingOrderRows(lines.reversed()).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        let order = text.components(separatedBy: "\n")
        XCTAssertEqual(order, (0..<8).map { "Left \($0)" } + (0..<8).map { "Right \($0)" })
    }

    func testATitleAcrossBothColumnsIsReadFirst() {
        var lines = [line("A title across the page", x: 20, y: 40, width: 530)]
        for (index, y) in stride(from: 100, to: 300, by: 40).enumerated() {
            lines.append(line("Left \(index)", x: 20, y: CGFloat(y), width: 230))
            lines.append(line("Right \(index)", x: 320, y: CGFloat(y), width: 230))
        }
        lines.append(line("A footer across the page", x: 20, y: 340, width: 530))
        let order = OCRLayout.readingOrderRows(lines).flatMap { $0 }.map(\.text)
        XCTAssertEqual(order.first, "A title across the page")
        XCTAssertEqual(order.last, "A footer across the page")
        XCTAssertEqual(Array(order[1...5]), (0..<5).map { "Left \($0)" })
    }

    func testSingleColumnReadsTopToBottom() {
        let lines = (0..<5).map { line("Line \($0)", x: 20, y: CGFloat(40 + $0 * 30), width: 400 - CGFloat($0 * 40)) }
        XCTAssertEqual(OCRLayout.readingOrderRows(lines.reversed()).flatMap { $0 }.map(\.text).joined(separator: "\n"), (0..<5).map { "Line \($0)" }.joined(separator: "\n"))
    }

    func testSlightlyTiltedParagraphStillReadsLineByLine() {
        // A photo of a page, 3° off: every upright box is much taller than
        // the text and overlaps the lines above and below.
        let tilt = 3 * CGFloat.pi / 180
        let lines = (0..<6).map { index -> OCRLine in
            let center = CGPoint(x: 500, y: 100 + CGFloat(index) * 32)
            let boxHeight = 20 * cos(tilt) + 900 * sin(tilt)
            let box = CGRect(x: center.x - 450, y: center.y - boxHeight / 2, width: 900, height: boxHeight)
            return OCRLine(text: "Sentence \(index)", box: box, textHeight: 20, angle: tilt)
        }
        XCTAssertEqual(OCRLayout.readingOrderRows(lines.reversed()).flatMap { $0 }.map(\.text).joined(separator: "\n"), (0..<6).map { "Sentence \($0)" }.joined(separator: "\n"))
    }

    func testRightToLeftRowsReadFromTheRight() {
        let rows = OCRLayout.rows(from: [
            line("שלום", x: 300, y: 40, width: 80),
            line("עולם", x: 100, y: 40, width: 80),
        ])
        XCTAssertEqual(rows.first?.map(\.text), ["שלום", "עולם"])
        XCTAssertTrue(OCRLayout.isRightToLeft("مرحبا"))
        XCTAssertFalse(OCRLayout.isRightToLeft("Hello"))
    }

    func testSpanningSubheadingFlushesBothColumnsAboveIt() {
        let lines = [
            line("Left above", x: 20, y: 20, width: 230),
            line("Right above", x: 320, y: 20, width: 230),
            line("Left above 2", x: 20, y: 50, width: 230),
            line("Right above 2", x: 320, y: 50, width: 230),
            line("Heading", x: 20, y: 90, width: 530),
            line("Left below", x: 20, y: 130, width: 230),
            line("Right below", x: 320, y: 130, width: 230),
        ]
        XCTAssertEqual(OCRLayout.readingOrderRows(lines.reversed()).flatMap { $0 }.map(\.text),
                       ["Left above", "Left above 2", "Right above", "Right above 2", "Heading", "Left below", "Right below"])
    }

    func testGridOfShortCellsReadsRowByRow() {
        let grid = [["Item", "Qty", "Price"], ["Pens", "12", "3.50"], ["Paper", "5", "8.00"], ["Ink", "2", "21.00"]]
        var lines: [OCRLine] = []
        for (row, cells) in grid.enumerated() {
            for (column, cell) in cells.enumerated() {
                lines.append(line(cell, x: CGFloat(20 + column * 160), y: CGFloat(30 + row * 40), width: CGFloat(cell.count * 11)))
            }
        }
        XCTAssertTrue(OCRLayout.isTable(lines))
        XCTAssertEqual(OCRLayout.readingOrderRows(lines.reversed()).map { $0.map(\.text) }, grid)
    }

    func testProseColumnsAreNotMistakenForATable() {
        let sentence = "the quick brown fox jumps over a lazy dog"
        var lines: [OCRLine] = []
        for (index, y) in stride(from: 40, to: 300, by: 30).enumerated() {
            lines.append(line("\(sentence) \(index)", x: 20, y: CGFloat(y), width: 240))
            lines.append(line("\(sentence) \(index + 20)", x: 300, y: CGFloat(y), width: 240))
        }
        XCTAssertFalse(OCRLayout.isTable(lines))
    }

    func testEmptyLayout() {
        XCTAssertTrue(OCRLayout.readingOrderRows([]).isEmpty)
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 18) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }
}
