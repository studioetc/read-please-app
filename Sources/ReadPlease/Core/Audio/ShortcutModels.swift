import AppKit
import Foundation
import KeyboardShortcuts

enum ShortcutAction: String, CaseIterable, Codable, Hashable, Sendable {
    case playPause
    case stop

    var title: String {
        switch self {
        case .playPause:
            "Play / Pause"
        case .stop:
            "Stop"
        }
    }

    var description: String {
        switch self {
        case .playPause:
            "Start reading the current selection, pause active playback, or resume paused playback."
        case .stop:
            "Stop the current speech immediately."
        }
    }

    var defaultBindings: [ShortcutBinding] {
        switch self {
        case .playPause:
            [
                // Primary (shown in Settings): Control-` (grave).
                ShortcutBinding(
                    id: "default.playPause.controlBacktick",
                    shortcut: .init(.backtick, modifiers: [.control]),
                    enabled: true,
                    source: .defaultValue
                ),
                // Secondary: retained F-key, editable via Advanced shortcuts (shortcuts.json).
                ShortcutBinding(
                    id: "default.playPause.f14",
                    shortcut: .init(.f14),
                    enabled: true,
                    source: .defaultValue
                ),
            ]
        case .stop:
            [
                // Primary (shown in Settings): Control-1.
                ShortcutBinding(
                    id: "default.stop.controlOne",
                    shortcut: .init(.one, modifiers: [.control]),
                    enabled: true,
                    source: .defaultValue
                ),
                // Secondary: retained F-key, editable via Advanced shortcuts (shortcuts.json).
                ShortcutBinding(
                    id: "default.stop.f15",
                    shortcut: .init(.f15),
                    enabled: true,
                    source: .defaultValue
                ),
            ]
        }
    }
}

enum ShortcutBindingSource: String, Codable, Hashable, Sendable {
    case defaultValue = "default"
    case custom
}

struct ShortcutBinding: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var description: String? = nil
    var shortcut: KeyboardShortcuts.Shortcut
    var enabled: Bool
    var source: ShortcutBindingSource

    var recorderNameRawValue: String {
        "ReadPlease.shortcut.\(id)"
    }

    var recorderName: KeyboardShortcuts.Name {
        .init(recorderNameRawValue)
    }
}

enum ShortcutStoreBannerTone {
    case info
    case success
    case error
}

struct ShortcutStoreBanner: Identifiable, Equatable {
    let id = UUID()
    let tone: ShortcutStoreBannerTone
    let text: String
}

enum ShortcutStoreError: LocalizedError {
    case duplicateID(String)
    case duplicateShortcut(String)
    case saveFailed(String)
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .duplicateID(let id):
            "The shortcut config contains a duplicate binding id: \(id)."
        case .duplicateShortcut(let shortcut):
            "The shortcut \(shortcut) is assigned more than once. Each shortcut can only trigger one action."
        case .saveFailed(let message):
            "Couldn't save shortcuts.json: \(message)"
        case .invalidConfig(let message):
            message
        }
    }
}
