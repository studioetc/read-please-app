// Adapted from Snapzy paragraph reflow (BSD-3-Clause). See THIRD_PARTY_NOTICES.md for pinned sources.
// BSD 3-Clause License
//
// Copyright (c) 2026, Trong Duong Duc
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Adapted from Text Grab IsWrappedParagraph / GroupWrappedParagraphLines (MIT). See THIRD_PARTY_NOTICES.md for pinned sources.
// MIT License
//
// Copyright (c) 2020 Joseph Finney
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

/// Repairs visual OCR wrapping without rewriting words or inventing speech emphasis.
@MainActor
enum SpeechTextFormatter {
    static func format(_ rows: [[OCRLine]]) -> String {
        // Keep grid rows distinct so values stay with their row labels. No tabs or extra pauses.
        let preservesTableRows = OCRLayout.isTable(rows.flatMap { $0 })
        let lines = rows.compactMap { row -> OCRLine? in
            let nonempty = row.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard let first = nonempty.first else { return nil }
            return OCRLine(
                text: nonempty.map(\.text).joined(separator: " "),
                box: nonempty.dropFirst().reduce(first.box) { $0.union($1.box) },
                textHeight: first.textHeight
            )
        }
        guard let first = lines.first else { return "" }
        let gutters = OCRLayout.columnGutters(rows.flatMap { $0 })
        func columnIndex(_ line: OCRLine) -> Int {
            gutters.filter { $0.upperBound <= line.box.midX }.count
        }
        var columnWidths: [Int: CGFloat] = [:]
        for line in lines {
            let spansGutter = gutters.contains { gutter in
                let middle = (gutter.lowerBound + gutter.upperBound) / 2
                return line.box.minX < middle && line.box.maxX > middle
            }
            guard !spansGutter else { continue }
            let index = columnIndex(line)
            columnWidths[index] = max(columnWidths[index] ?? 0, line.box.width)
        }
        var output = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (previous, line) in zip(lines, lines.dropFirst()) {
            let fragment = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let columnWidth = columnWidths[columnIndex(previous)] ?? previous.box.width
            if preservesTableRows {
                output += "\n" + fragment
            } else if !isWrappedParagraph(previous, line) {
                output += "\n\n" + fragment
            } else if startsList(fragment) {
                // A visible list marker starts a row; do not invent a blank paragraph.
                output += "\n" + fragment
            } else if output.hasSuffix("-"),
                      output.dropLast().last?.isWhitespace == false {
                // Vision can recognize a spaced em/en dash as ASCII " -". That is
                // punctuation, not a word split: retain the space after it on reflow.
                // A short hyphen-ended row is evidence of an explicit source break.
                // Full-width rows may be visual wraps, but a dictionary cannot tell a
                // compound from discretionary hyphenation. Never rewrite the word.
                output += (previous.box.width < columnWidth * 0.85 ? "\n" : "") + fragment
            } else if let first = fragment.first, ",.;:!?)]}%".contains(first) {
                output += fragment
            } else if let last = output.unicodeScalars.last,
                      let first = fragment.unicodeScalars.first,
                      isCJK(last), isCJK(first) {
                output += fragment
            } else {
                output += " " + fragment
            }
        }
        return output
    }

    private static func isWrappedParagraph(_ previous: OCRLine, _ next: OCRLine) -> Bool {
        let minHeight = min(previous.textHeight, next.textHeight)
        let maxHeight = max(previous.textHeight, next.textHeight)
        guard minHeight > 0, maxHeight / minHeight <= 1.5,
              next.box.minY - previous.box.minY >= minHeight * 0.5 else { return false }
        // A column transition or an indented block starts a new paragraph.
        let overlap = min(previous.box.maxX, next.box.maxX) - max(previous.box.minX, next.box.minX)
        let indent = OCRLayout.isRightToLeft(previous.text)
            ? previous.box.maxX - next.box.maxX : next.box.minX - previous.box.minX
        guard overlap > 0, indent <= maxHeight * 0.5 || startsList(previous.text) else { return false }
        return next.box.minY - previous.box.maxY < (previous.textHeight + next.textHeight) * 0.3
    }

    private static func startsList(_ text: String) -> Bool {
        text.range(of: #"^(?:[•*\-–]\s|[0-9]+[.)]\s)"#, options: .regularExpression) != nil
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: true
        default: false
        }
    }
}
