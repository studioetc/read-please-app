import AppKit
import CoreGraphics

@MainActor
enum ScreenRecordingPermission {
    /// Non-prompting. Capture backends decide when a user-initiated request is appropriate.
    static func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Call only from an explicit user action, such as the permission-needed menu button.
    @discardableResult
    static func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
