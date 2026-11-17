import Foundation
import KeyboardShortcuts

@MainActor
final class ShortcutManager: @unchecked Sendable {
    static let shared = ShortcutManager()

    var onAction: ((ShortcutAction) -> Void)?
    private var listenerTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func registerBindings(_ bindingsByAction: [ShortcutAction: [ShortcutBinding]]) {
        listenerTasks.values.forEach { $0.cancel() }
        listenerTasks.removeAll()

        for action in ShortcutAction.allCases {
            for binding in bindingsByAction[action] ?? [] where binding.enabled {
                let recorderName = binding.recorderName
                let taskID = binding.id

                ScreenAreaTiming.logger.notice("shortcut_registered action=\(action.rawValue, privacy: .public) key=\(binding.shortcut.carbonKeyCode) enabled=\(binding.enabled)")
                listenerTasks[taskID] = Task { [weak self] in
                    for await _ in KeyboardShortcuts.events(.keyUp, for: recorderName) {
                        guard !Task.isCancelled else { return }
                        self?.handle(action)
                    }
                }
            }
        }
    }

    private func handle(_ action: ShortcutAction) {
        ScreenAreaTiming.logger.notice("shortcut_received action=\(action.rawValue, privacy: .public)")
        onAction?(action)
    }
}
