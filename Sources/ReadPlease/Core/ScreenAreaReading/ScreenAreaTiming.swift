import Foundation
import os

/// A task-local trace follows one invocation across capture, OCR and playback. All durations
/// use ContinuousClock; wall-clock changes cannot distort phase measurements.
struct ScreenAreaTiming: Sendable {
    @TaskLocal static var current: ScreenAreaTiming?
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.onestepp.ReadPlease",
                               category: "ScreenAreaReading")
    let id = UUID().uuidString
    let started = ContinuousClock.now

    func event(_ phase: String, since phaseStart: ContinuousClock.Instant? = nil, detail: String = "") {
        let now = ContinuousClock.now
        let elapsed = Self.milliseconds(started.duration(to: now))
        let duration = Self.milliseconds((phaseStart ?? started).duration(to: now))
        Self.logger.notice("trace=\(id, privacy: .public) phase=\(phase, privacy: .public) elapsed_ms=\(elapsed) phase_ms=\(duration) \(detail, privacy: .public)")
    }

    func recognizedText(_ text: String) {
        Self.debugText(text, label: "recognized_text", trace: id)
    }

    static func selectionText(_ text: String) {
        debugText(text, label: "selection_text")
    }

    func recognizedLines(_ lines: [OCRLine]) {
        guard Self.logsText else { return }
        // One bounded record per line avoids unified-log truncation on paragraph captures.
        for (index, line) in lines.enumerated() {
            let record: [String: Any] = ["text": line.text, "x": line.box.minX, "y": line.box.minY,
                                        "width": line.box.width, "height": line.box.height,
                                        "textHeight": line.textHeight]
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { continue }
            Self.logger.notice("trace=\(id, privacy: .public) recognized_line[\(index)]=\(json, privacy: .public)")
        }
    }

    private static var logsText: Bool {
        Bundle.main.bundleIdentifier == "com.onestepp.ReadPlease.staging"
            && UserDefaults.standard.bool(forKey: "ReadScreenAreaDebugLogText")
    }

    private static func debugText(_ text: String, label: String, trace: String = "selection") {
        // Production never logs user text, even if the opt-in preference is copied there.
        guard logsText else { return }
        // JSON keeps newlines and whitespace unambiguous in character-level comparisons.
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else { return }
        Self.logger.notice("trace=\(trace, privacy: .public) \(label, privacy: .public)=\(json, privacy: .public)")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
