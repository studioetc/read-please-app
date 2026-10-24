// Adapted from Shotnix OCRLine (MIT). See THIRD_PARTY_NOTICES.md for pinned sources.
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

import CoreGraphics

/// One recognized line, in image pixels with a top-left origin.
struct OCRLine: Equatable, Sendable {
    let text: String
    let confidence: Float
    /// Upright bounding box, top-left origin, in pixels.
    let box: CGRect
    /// The text's own height: less than the box's when the line is tilted.
    var textHeight: CGFloat
    /// Baseline tilt in radians, positive when it runs down to the right.
    var angle: CGFloat

    init(text: String, box: CGRect, textHeight: CGFloat? = nil, angle: CGFloat = 0, confidence: Float = 1) {
        self.text = text
        self.confidence = confidence
        self.box = box
        self.textHeight = textHeight ?? box.height
        self.angle = angle
    }
}
