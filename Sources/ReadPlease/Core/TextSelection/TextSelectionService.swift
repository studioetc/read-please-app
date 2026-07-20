import AppKit
import ApplicationServices
import Carbon

@MainActor
public final class TextSelectionService {
    public static let shared = TextSelectionService()

    private static let transientPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )
    private static let captureMarkerPasteboardType = NSPasteboard.PasteboardType(
        "com.onestepp.ReadPlease.clipboard-capture"
    )

    // Toggle to allow Cmd+C clipboard fallback when AX fails
    public var enableClipboardFallback: Bool = true

    private var accessibilityRestrictedApps = Set<String>()
    private var activationObserver: NSObjectProtocol?
    private var lastActiveExternalApp: NSRunningApplication?
    private var isClipboardCaptureInProgress = false

    // Apps known to need clipboard fallback (poor AX support)
    private let clipboardFallbackApps = [
        // Code Editors
        "com.microsoft.VSCode", "com.visualstudio.code", "com.apple.dt.Xcode",
        "com.sublimetext", "io.cursor", "com.panic.Nova", "com.barebones.bbedit",
        "org.vim", "com.jetbrains", "com.googlecode.iterm2",
        // Chat/Electron Apps
        "com.openai.chat", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        // Browsers (for web apps like ChatGPT web)
        "com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
    ]

    private let editorKeywords = ["code", "editor", "studio", "ide", "terminal"]
    private let readPleaseBundlePrefix = "com.onestepp.ReadPlease"

    private init() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            updateLastActiveExternalApp(with: frontmostApp)
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor in
                self.updateLastActiveExternalApp(with: app)
            }
        }
    }

    public func checkAccessibilityPermissions() -> Bool {
        // kAXTrustedCheckOptionPrompt is not Sendable in Swift 6, using literal key
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Non-prompting trust check — safe to call at launch without triggering the system dialog.
    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func getSelectedText() async -> String? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier ?? ""
        let appName = frontApp?.localizedName?.lowercased() ?? ""

        if let frontApp {
            updateLastActiveExternalApp(with: frontApp)
        }

        print("TextSelectionService: Target App: \(appName) (\(bundleID))")

        // Try Accessibility first
        if let axText = getSelectedTextViaAccessibility() {
            return axText
        }

        // Optional clipboard fallback (disabled by default)
        guard enableClipboardFallback else {
            print("TextSelectionService: No AX text and clipboard fallback disabled.")
            return nil
        }

        // Check strict fallback list when enabled
        if isLikelyEditor(bundleID: bundleID, appName: appName)
            || accessibilityRestrictedApps.contains(bundleID)
        {
            print("TextSelectionService: Using clipboard fallback for editor/restricted app.")
            return await getSelectedTextViaClipboard()
        }

        return await getSelectedTextViaClipboard()
    }

    public func getSelectedTextFromLastActiveAppViaAccessibility() -> String? {
        guard let lastActiveExternalApp else {
            print("TextSelectionService: No last active external app available.")
            return nil
        }

        let appDescription =
            "\(lastActiveExternalApp.localizedName ?? "unknown") (\(lastActiveExternalApp.bundleIdentifier ?? "unknown"))"
        print("TextSelectionService: Targeting last active external app: \(appDescription)")

        return getSelectedTextViaAccessibility(for: lastActiveExternalApp)
    }

    private func isLikelyEditor(bundleID: String, appName: String) -> Bool {
        if clipboardFallbackApps.contains(where: { bundleID.hasPrefix($0) }) { return true }
        if editorKeywords.contains(where: {
            bundleID.lowercased().contains($0) || appName.contains($0)
        }) {
            return true
        }
        return false
    }

    private func updateLastActiveExternalApp(with app: NSRunningApplication) {
        guard !isReadPleaseApplication(app) else { return }
        lastActiveExternalApp = app
    }

    private func isReadPleaseApplication(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }

        return (app.bundleIdentifier ?? "").hasPrefix(readPleaseBundlePrefix)
    }

    private func getSelectedTextViaAccessibility() -> String? {
        // Check permissions first
        let isTrusted = AXIsProcessTrusted()
        print("TextSelectionService: AXIsProcessTrusted = \(isTrusted)")

        if !isTrusted {
            print("TextSelectionService: ❌ NOT TRUSTED - Cannot use Accessibility API")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard err == .success, let app = focusedApp else {
            print("TextSelectionService: Could not get focused app (AXError: \(axErrorName(err)))")
            return nil
        }

        return getSelectedTextViaAccessibility(
            in: app as! AXUIElement,
            appDescription: "frontmost application"
        )
    }

    private func getSelectedTextViaAccessibility(for app: NSRunningApplication) -> String? {
        let isTrusted = AXIsProcessTrusted()
        print("TextSelectionService: AXIsProcessTrusted = \(isTrusted)")

        guard isTrusted else {
            print("TextSelectionService: ❌ NOT TRUSTED - Cannot use targeted Accessibility API")
            return nil
        }

        let appDescription =
            "\(app.localizedName ?? "unknown") (\(app.bundleIdentifier ?? "unknown"))"
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return getSelectedTextViaAccessibility(in: axApp, appDescription: appDescription)
    }

    private func getSelectedTextViaAccessibility(
        in app: AXUIElement,
        appDescription: String
    ) -> String? {
        print("TextSelectionService: Reading selection via Accessibility from \(appDescription)")

        var focusedElement: CFTypeRef?
        let errElement = AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard errElement == .success, let element = focusedElement else {
            print(
                "TextSelectionService: Could not get focused element (AXError: \(axErrorName(errElement)))"
            )
            return nil
        }

        // Log element info
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        print("TextSelectionService: Focused element role: \(role as? String ?? "unknown")")

        var selectedText: CFTypeRef?
        let errText = AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        if errText == .success, let text = selectedText as? String {
            if text.isEmpty {
                print("TextSelectionService: Selected text is empty string")
                return nil
            }
            print("TextSelectionService: ✅ Got selected text: '\(text.prefix(50))...'")
            return text
        }

        print(
            "TextSelectionService: Failed to get selected text (AXError: \(axErrorName(errText)))")
        return nil
    }

    private func axErrorName(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(error.rawValue))"
        }
    }

    private func getSelectedTextViaClipboard() async -> String? {
        guard !isClipboardCaptureInProgress else {
            print("TextSelectionService: Clipboard capture already in progress.")
            return nil
        }
        isClipboardCaptureInProgress = true
        defer { isClipboardCaptureInProgress = false }

        let pasteboard = NSPasteboard.general

        // 1. Save existing clipboard items
        var savedItems: [NSPasteboardItem] = []
        if let currentItems = pasteboard.pasteboardItems {
            for item in currentItems {
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                savedItems.append(newItem)
            }
        }

        // Replace the current contents with a private, transient marker before copying. Keeping
        // the marker out of the public string type prevents it from being pasted or recorded as
        // text by clipboard managers while still giving us a fresh ownership change to observe.
        let captureChangeCount = Self.prepareClipboardForCapture(pasteboard)

        defer {
            restorePasteboard(savedItems, on: pasteboard)
        }

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC = CGKeyCode(kVK_ANSI_C)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)

        // Poll without blocking the main actor. Clipboard owners may provide their data lazily,
        // so wait for both an ownership change and copied text.
        for _ in 0..<20 {
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return nil
            }

            if let copiedText = Self.validatedClipboardText(
                changeCount: pasteboard.changeCount,
                captureChangeCount: captureChangeCount,
                text: pasteboard.string(forType: .string)
            ) {
                return copiedText
            }
        }

        return nil
    }

    static func validatedClipboardText(
        changeCount: Int,
        captureChangeCount: Int,
        text: String?
    ) -> String? {
        guard changeCount != captureChangeCount, let text else { return nil }
        return text
    }

    @discardableResult
    static func prepareClipboardForCapture(_ pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: transientPasteboardType)
        pasteboard.setString(UUID().uuidString, forType: captureMarkerPasteboardType)
        return pasteboard.changeCount
    }

    private func restorePasteboard(_ items: [NSPasteboardItem], on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
