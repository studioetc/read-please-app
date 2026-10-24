// Adapted from TRex performModernRecognition / recognizeWithModernAPI (MIT). See THIRD_PARTY_NOTICES.md for pinned sources.
// MIT License
//
// Copyright (c) 2021 Ameba Labs
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

// Adapted from Shotnix observation-to-pixel geometry (MIT). See THIRD_PARTY_NOTICES.md for pinned sources.
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
import CoreText
import Vision

struct TextRecognizer: Sendable {
    /// Empty uses Vision's default (English) with automatic language detection.
    /// Callers can supply other supported languages without adding a language UI.
    var languages: [Locale.Language] = []

    @concurrent
    func recognize(_ region: CapturedRegion) async throws -> [OCRLine] {
        try Task.checkCancellation()
        do {
            return try await perform(on: region.image, level: .accurate)
        } catch {
            guard !(error is CancellationError), !Task.isCancelled else {
                throw CancellationError()
            }
            // A fresh fast request can recover from an accurate-model/Neural Engine failure.
            return try await perform(on: region.image, level: .fast)
        }
    }

    /// Load the same accurate Vision model with app-owned pixels, off the main actor. This
    /// never captures the desktop, asks for permission, speaks, or logs user content.
    @concurrent
    static func warmUp() async {
        let timing = ScreenAreaTiming()
        timing.event("vision_warmup_started")
        guard let context = CGContext(data: nil, width: 640, height: 128, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 128))
        let text = NSAttributedString(string: "ReadPlease ready to read.", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 40, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 20, y: 50)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { return }
        do {
            _ = try await TextRecognizer().recognize(CapturedRegion(image: image))
            timing.event("vision_warmup_done")
        } catch {
            // A failed warm-up never disables the ordinary accurate→fast capture path.
            timing.event("vision_warmup_failed")
        }
    }

    private func perform(
        on image: CGImage,
        level: RecognizeTextRequest.RecognitionLevel
    ) async throws -> [OCRLine] {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        let supported = request.supportedRecognitionLanguages
        let preferred = languages.filter { supported.contains($0) }
        request.automaticallyDetectsLanguage = preferred.isEmpty
        if !preferred.isEmpty {
            request.recognitionLanguages = preferred
        }
        request.minimumTextHeightFraction = 0

        let observations = try await request.perform(on: image, orientation: .up)
        try Task.checkCancellation()
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let box = observation.boundingBox.cgRect
            let baselineX = (observation.bottomRight.x - observation.bottomLeft.x) * width
            let baselineY = (observation.bottomRight.y - observation.bottomLeft.y) * height
            let leftHeight = hypot(
                (observation.topLeft.x - observation.bottomLeft.x) * width,
                (observation.topLeft.y - observation.bottomLeft.y) * height
            )
            let rightHeight = hypot(
                (observation.topRight.x - observation.bottomRight.x) * width,
                (observation.topRight.y - observation.bottomRight.y) * height
            )
            return OCRLine(
                text: text,
                box: CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                            width: box.width * width, height: box.height * height),
                textHeight: (leftHeight + rightHeight) / 2,
                angle: -atan2(baselineY, baselineX),
                confidence: candidate.confidence
            )
        }
    }
}
