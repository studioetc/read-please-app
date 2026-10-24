import Foundation
@testable import ReadPlease

/// Desktop captures on DELL U2718Q, 2026-10-25. Expected is exact selection input.
/// Only the explicitly recorded Vision glyph substitutions are allowed in comparisons;
/// they are not replacements made by the app. Geometry is in capture pixels.
struct SelectionParityFixture {
    let name: String
    let expected: String
    let visionGlyphs: [(String, String)]
    let lines: [OCRLine]

    var expectedWithVisionGlyphs: String {
        visionGlyphs.reduce(expected) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

@MainActor
enum SelectionParityFixtures {
    static let corpus: [SelectionParityFixture] = [
        SelectionParityFixture(
            name: "original-preview",
            expected: "Hello world — typed in background Hello world — typed in background Hello world — typed in background",
            visionGlyphs: [("—", "-")],
            lines: [
                OCRLine(text: "Hello world - typed in", box: CGRect(x: 8.0000, y: 20.0000, width: 964.0000, height: 96.0000), textHeight: 96.0000),
                OCRLine(text: "background Hello world -", box: CGRect(x: 10.0000, y: 136.0000, width: 1124.0000, height: 98.0000), textHeight: 98.0000),
                OCRLine(text: "typed in background Hello", box: CGRect(x: 2.0000, y: 252.0000, width: 1120.0000, height: 98.0000), textHeight: 98.0000),
                OCRLine(text: "world - typed in background", box: CGRect(x: 12.0000, y: 370.0000, width: 1240.0000, height: 92.0000), textHeight: 92.0000),
            ]
        ),
        SelectionParityFixture(
            name: "original-safari",
            expected: "Hello world — typed in background Hello world — typed in background Hello world — typed in background",
            visionGlyphs: [("—", "-")],
            lines: [
                OCRLine(text: "Hello world - typed in", box: CGRect(x: 4.3372, y: 19.5242, width: 1132.0116, height: 110.6371), textHeight: 110.6371),
                OCRLine(text: "background Hello world -", box: CGRect(x: 13.0117, y: 154.0000, width: 1320.6802, height: 111.0000), textHeight: 111.0000),
                OCRLine(text: "typed in background Hello", box: CGRect(x: 4.3372, y: 290.6936, width: 1309.8372, height: 110.6371), textHeight: 110.6371),
                OCRLine(text: "world - typed in background", box: CGRect(x: 13.0116, y: 425.0000, width: 1452.9651, height: 111.0000), textHeight: 111.0000),
            ]
        ),
        SelectionParityFixture(
            name: "article",
            expected: "A quieter street\n\nThe council opened a small garden beside the station. Volunteers planted herbs, repaired the old bench, and left a wide path for people walking home. The well-known corner now feels welcoming.\n\nOn Sunday, neighbours brought tea and shared stories. “It’s a modest start,” said Maya, “but we’re staying.” The next working bee runs from 9–11 am — everyone is welcome.",
            visionGlyphs: [("“", "\""), ("”", "\""), ("’", "'"), ("–", "-")],
            lines: [
                OCRLine(text: "A quieter street", box: CGRect(x: 8.0000, y: 10.0000, width: 212.0000, height: 30.0000), textHeight: 30.0000),
                OCRLine(text: "The council opened a small garden beside the station. Volunteers planted", box: CGRect(x: 8.0000, y: 82.0000, width: 998.0000, height: 32.0000), textHeight: 32.0000),
                OCRLine(text: "herbs, repaired the old bench, and left a wide path for people walking", box: CGRect(x: 4.3000, y: 115.5190, width: 950.3000, height: 34.4810), textHeight: 34.4810),
                OCRLine(text: "home. The well-known corner now feels welcoming.", box: CGRect(x: 8.0000, y: 154.0000, width: 700.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "On Sunday, neighbours brought tea and shared stories. \"It's a modest", box: CGRect(x: 10.0000, y: 222.0000, width: 944.0000, height: 38.0000), textHeight: 38.0000),
                OCRLine(text: "start,\" said Maya, \"but we're staying.\" The next working bee runs from 9-", box: CGRect(x: 8.0000, y: 260.0000, width: 988.0000, height: 38.0000), textHeight: 38.0000),
                OCRLine(text: "11 am — everyone is welcome.", box: CGRect(x: 10.0000, y: 300.0000, width: 430.0000, height: 32.0000), textHeight: 32.0000),
            ]
        ),
        SelectionParityFixture(
            name: "punctuation",
            expected: "A reader’s notebook\n\n“Don’t rush,” she said. “We’ll finish tomorrow.” The editor’s note — written at 8–9 pm — asked: who’s coming, and why?\n\nA well-known writer called it a long-term project. The re-creation wasn’t a correction; it was a fresh reading. (Keep the words, quotes, and punctuation.)",
            visionGlyphs: [("“", "\""), ("”", "\""), ("’", "'"), ("–", "-")],
            lines: [
                OCRLine(text: "A reader's notebook", box: CGRect(x: 8.0000, y: 10.0000, width: 276.0000, height: 26.0000), textHeight: 26.0000),
                OCRLine(text: "\"Don't rush,\" she said. \"We'll finish tomorrow.\" The editor's note — written", box: CGRect(x: 5.8809, y: 70.6726, width: 986.2822, height: 46.5351), textHeight: 39.1780),
                OCRLine(text: "at 8-9 pm — asked: who's coming, and why?", box: CGRect(x: 8.0000, y: 116.0000, width: 616.0000, height: 36.0000), textHeight: 36.0000),
                OCRLine(text: "A well-known writer called it a long-term project. The re-creation wasn't a", box: CGRect(x: 8.6000, y: 188.0000, width: 984.7000, height: 34.4810), textHeight: 34.4810),
                OCRLine(text: "correction; it was a fresh reading. (Keep the words, quotes, and", box: CGRect(x: 8.0000, y: 226.0000, width: 862.0000, height: 36.0000), textHeight: 36.0000),
                OCRLine(text: "punctuation.)", box: CGRect(x: 9.5718, y: 266.4677, width: 181.0070, height: 31.1331), textHeight: 30.5716),
            ]
        ),
        SelectionParityFixture(
            name: "list",
            expected: "Weekend checklist\n\n1. Book the train for Saturday.\n2. Pack a well-made raincoat.\n3. Check the weather before leaving.\n\n• Bring lunch and water.\n• Don’t forget the map.\n• Call Sam — then go home.",
            visionGlyphs: [("’", "'"), ("—", "-")],
            lines: [
                OCRLine(text: "Weekend checklist", box: CGRect(x: 8.0000, y: 8.0000, width: 260.0000, height: 28.0000), textHeight: 28.0000),
                OCRLine(text: "1. Book the train for Saturday.", box: CGRect(x: 10.0000, y: 82.0000, width: 400.0000, height: 32.0000), textHeight: 32.0000),
                OCRLine(text: "2. Pack a well-made raincoat.", box: CGRect(x: 8.0000, y: 118.0000, width: 404.0000, height: 30.0000), textHeight: 30.0000),
                OCRLine(text: "3. Check the weather before leaving.", box: CGRect(x: 8.0000, y: 154.0000, width: 502.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "• Bring lunch and water.", box: CGRect(x: 4.0000, y: 226.0000, width: 334.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "• Don't forget the map.", box: CGRect(x: 4.0000, y: 264.0000, width: 316.0000, height: 32.0000), textHeight: 32.0000),
                OCRLine(text: "• Call Sam - then go home.", box: CGRect(x: 0.0000, y: 300.0000, width: 400.0000, height: 34.0000), textHeight: 34.0000),
            ]
        ),
        SelectionParityFixture(
            name: "numbers",
            expected: "October account\n\nOn 25/10/2026, invoice 1042 totalled $1,234.50. We paid $200.00 on 24 October; the balance is $1,034.50. Tax was 10%, and the exchange rate was 0.65.\n\nPlease review pages 10–12 by 3:30 pm. The reference is AB-204, the quantity is 2.5 kg, and the budget range is $900–$1,100.",
            visionGlyphs: [("–", "-")],
            lines: [
                OCRLine(text: "October account", box: CGRect(x: 10.0000, y: 8.0000, width: 232.0000, height: 28.0000), textHeight: 28.0000),
                OCRLine(text: "On 25/10/2026, invoice 1042 totalled $1,234.50. We paid $200.00 on 24", box: CGRect(x: 10.0000, y: 82.0000, width: 970.0000, height: 32.0000), textHeight: 32.0000),
                OCRLine(text: "October; the balance is $1,034.50. Tax was 10%, and the exchange rate", box: CGRect(x: 10.0000, y: 116.0000, width: 976.0000, height: 38.0000), textHeight: 38.0000),
                OCRLine(text: "was 0.65.", box: CGRect(x: 7.6684, y: 152.5489, width: 134.6633, height: 34.9021), textHeight: 32.0000),
                OCRLine(text: "Please review pages 10-12 by 3:30 pm. The reference is AB-204, the", box: CGRect(x: 10.0000, y: 228.0000, width: 934.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "quantity is 2.5 kg, and the budget range is $900-$1,100.", box: CGRect(x: 8.0000, y: 262.0000, width: 768.0000, height: 36.0000), textHeight: 36.0000),
            ]
        ),
        SelectionParityFixture(
            name: "hyphenation",
            expected: "Reading across lines\n\nThe well-known author discussed inter-\nnational cooperation with a decision-\nmaking group. Keep this deliberately typed line-end hyphenation exactly as selected.\n\nAn exam-\nple can be ambiguous in a screenshot. A self-\ncontained note should keep its hyphen. No spelling corrections are requested.",
            visionGlyphs: [],
            lines: [
                OCRLine(text: "Reading across lines", box: CGRect(x: 9.4878, y: 7.6742, width: 284.8969, height: 37.6675), textHeight: 32.5037),
                OCRLine(text: "The well-known author discussed inter-", box: CGRect(x: 4.3000, y: 81.8763, width: 533.2000, height: 30.1649), textHeight: 30.1649),
                OCRLine(text: "national cooperation with a decision-", box: CGRect(x: 7.6935, y: 111.9897, width: 502.5393, height: 40.3876), textHeight: 33.8272),
                OCRLine(text: "making group. Keep this deliberately typed line-end hyphenation exactly", box: CGRect(x: 10.0000, y: 152.0000, width: 980.0000, height: 36.0000), textHeight: 36.0000),
                OCRLine(text: "as selected.", box: CGRect(x: 8.0000, y: 192.0000, width: 170.0000, height: 28.0000), textHeight: 28.0000),
                OCRLine(text: "An exam-", box: CGRect(x: 7.9081, y: 265.5106, width: 136.1837, height: 26.9789), textHeight: 26.0000),
                OCRLine(text: "ple can be ambiguous in a screenshot. A self-", box: CGRect(x: 10.0000, y: 298.0000, width: 626.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "contained note should keep its hyphen. No spelling corrections are", box: CGRect(x: 8.0000, y: 336.0000, width: 908.0000, height: 34.0000), textHeight: 34.0000),
                OCRLine(text: "requested.", box: CGRect(x: 7.8392, y: 369.3086, width: 152.3215, height: 37.3827), textHeight: 36.0000),
            ]
        ),
    ]
}
