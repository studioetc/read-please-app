// Adapted from Shotnix OCRLayout (MIT). See THIRD_PARTY_NOTICES.md for pinned sources.
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

/// Reading order over recognized lines. Pure
/// geometry, so it's tested with hand-made boxes as well as real OCR.
enum OCRLayout {

    /// Lines grouped into visual rows (top to bottom), each row left to right.
    /// Measured along the text's own tilt, so a slightly rotated page (a
    /// photo of a receipt, say) still reads line by line.
    static func rows(from lines: [OCRLine]) -> [[OCRLine]] {
        guard !lines.isEmpty else { return [] }
        let angles = lines.map(\.angle).sorted()
        let tilt = angles[angles.count / 2]
        let upright = abs(tilt) < 0.5 * .pi / 180
        let sinTilt = upright ? 0 : sin(tilt)
        let cosTilt = upright ? 1 : cos(tilt)
        func across(_ line: OCRLine) -> CGFloat { line.box.midY * cosTilt - line.box.midX * sinTilt }
        func along(_ line: OCRLine) -> CGFloat { line.box.midX * cosTilt + line.box.midY * sinTilt }

        var rows: [(position: CGFloat, height: CGFloat, lines: [OCRLine])] = []
        for line in lines.sorted(by: { across($0) < across($1) }) {
            // Same row when its middle is within half a line of the row's.
            // The row doesn't grow as lines join, so a tall box can't swallow
            // the lines above and below it.
            if let last = rows.last, across(line) - last.position < 0.5 * max(last.height, line.textHeight) {
                rows[rows.count - 1].lines.append(line)
                rows[rows.count - 1].height = max(last.height, line.textHeight)
                continue
            }
            rows.append((across(line), line.textHeight, [line]))
        }
        return rows.map { row in
            // Arabic and Hebrew rows read right to left.
            let rightToLeft = row.lines.filter { isRightToLeft($0.text) }.count * 2 > row.lines.count
            return row.lines.sorted { rightToLeft ? along($0) > along($1) : along($0) < along($1) }
        }
    }

    /// Whether the text's first strongly directional letter is Hebrew or Arabic.
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            default: return false
            }
        }
        return false
    }

    /// Rows in reading order: a column is read top to bottom before the one
    /// to its right. A line running across the gutter (a title, a caption)
    /// ends the columns above it and is read in place.
    static func readingOrderRows(_ lines: [OCRLine]) -> [[OCRLine]] {
        guard lines.count > 1 else { return lines.isEmpty ? [] : [lines] }
        if isTable(lines) { return rows(from: lines) }
        let gutters = columnGutters(lines)
        guard !gutters.isEmpty else { return rows(from: lines) }

        var ordered: [[OCRLine]] = []
        var band: [OCRLine] = []
        func flushBand() {
            let columns = Dictionary(grouping: band) { line in
                gutters.filter { $0.upperBound <= line.box.midX }.count
            }
            for index in columns.keys.sorted() {
                ordered += rows(from: columns[index] ?? [])
            }
            band.removeAll()
        }
        for line in lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            let crossesGutter = gutters.contains { gutter in
                let middle = (gutter.lowerBound + gutter.upperBound) / 2
                return line.box.minX < middle && line.box.maxX > middle
            }
            if crossesGutter {
                flushBand()
                ordered.append([line])
            } else {
                band.append(line)
            }
        }
        flushBand()
        return ordered
    }

    /// Vertical whitespace running between side-by-side columns of text.
    static func columnGutters(_ lines: [OCRLine]) -> [ClosedRange<CGFloat>] {
        guard let minX = lines.map(\.box.minX).min(), let maxX = lines.map(\.box.maxX).max(), maxX > minX else { return [] }
        let contentWidth = maxX - minX
        let lineHeight = median(lines.map(\.box.height))
        // Full-width lines (titles over both columns) would bridge every
        // gutter, so gutters are found from the narrower lines.
        let narrow = lines.filter { $0.box.width < contentWidth * 0.6 }
        guard narrow.count >= 4 else { return [] }
        let allowedCrossings = narrow.count >= 10 ? narrow.count / 10 : 0

        var events = narrow.flatMap { [($0.box.minX, 1), ($0.box.maxX, -1)] }
        events.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        var coverage = 0
        var gapStart: CGFloat?
        var gaps: [ClosedRange<CGFloat>] = []
        for (x, delta) in events {
            let before = coverage
            coverage += delta
            if before > allowedCrossings, coverage <= allowedCrossings {
                gapStart = x
            } else if before <= allowedCrossings, coverage > allowedCrossings, let start = gapStart {
                if x > start { gaps.append(start...x) }
                gapStart = nil
            }
        }

        return gaps.filter { gap in
            guard gap.upperBound - gap.lowerBound >= max(lineHeight * 0.75, 4) else { return false }
            let left = narrow.filter { $0.box.maxX <= gap.lowerBound + 0.5 }
            let right = narrow.filter { $0.box.minX >= gap.upperBound - 0.5 }
            guard left.count >= 2, right.count >= 2,
                  let leftTop = left.map(\.box.minY).min(), let leftBottom = left.map(\.box.maxY).max(),
                  let rightTop = right.map(\.box.minY).min(), let rightBottom = right.map(\.box.maxY).max() else { return false }
            // Columns sit side by side: their vertical extents overlap.
            let overlap = min(leftBottom, rightBottom) - max(leftTop, rightTop)
            return overlap >= 0.3 * min(leftBottom - leftTop, rightBottom - rightTop)
        }
    }

    /// A grid: most rows have two or more cells, and the cells line up into
    /// the same columns row after row. What tells a table from a page set in
    /// columns: table columns sit far apart relative to their short cells
    /// (a text gutter is narrow next to its lines), or the cells are numbers.
    static func isTable(_ lines: [OCRLine]) -> Bool {
        let rows = rows(from: lines)
        let multiCell = rows.filter { $0.count >= 2 }
        guard multiCell.count >= 2, Double(multiCell.count) >= Double(rows.count) * 0.6 else { return false }

        var spans: [ClosedRange<CGFloat>] = []
        for cell in multiCell.flatMap({ $0 }).sorted(by: { $0.box.minX < $1.box.minX }) {
            let range = cell.box.minX...cell.box.maxX
            if let last = spans.last, range.lowerBound <= last.upperBound {
                spans[spans.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                spans.append(range)
            }
        }
        guard spans.count >= 2 else { return false }

        // By left edge: every grid cell starts inside its own column's span,
        // and a line running across several columns lands in the first.
        func column(for cell: OCRLine) -> Int {
            if let index = spans.firstIndex(where: { $0.contains(cell.box.minX) }) { return index }
            return spans.indices.min { abs(spans[$0].lowerBound - cell.box.minX) < abs(spans[$1].lowerBound - cell.box.minX) } ?? 0
        }
        for row in multiCell {
            let columns = row.map(column(for:))
            guard Set(columns).count == columns.count else { return false }
        }
        let cells = multiCell.flatMap { $0 }
        let averageWords = Double(cells.map { $0.text.split(separator: " ").count }.reduce(0, +)) / Double(max(cells.count, 1))
        let numberLike = cells.filter { cell in
            cell.text.allSatisfy { $0.isNumber || ".,:%$€£¥+-–/ ".contains($0) } && cell.text.contains(where: \.isNumber)
        }.count
        let widths = cells.map(\.box.width).sorted()
        let medianWidth = max(widths[widths.count / 2], 1)
        let gaps = zip(spans, spans.dropFirst()).map { $1.lowerBound - $0.upperBound }.sorted()
        let gapRatio = gaps[gaps.count / 2] / medianWidth
        let isTable = Double(numberLike) >= Double(cells.count) * 0.25
            || (averageWords <= 4 && gapRatio >= 0.9)
            || (spans.count >= 3 && averageWords <= 3 && gapRatio >= 0.5)
        return isTable
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
