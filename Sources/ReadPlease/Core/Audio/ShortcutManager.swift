import Foundation
import KeyboardShortcuts

@MainActor
final class ShortcutManager: @unchecked Sendable {
    static let shared = ShortcutManager()

    var onAction: ((ShortcutAction) -> Void)?
    private var listenerTasks: [String: Task<Void, Never>] = [:]
    private var isRecorderActive = false

    private init() {}

    func registerBindings(_ bindingsByAction: [ShortcutAction: [ShortcutBinding]]) {
        listenerTasks.values.forEach { $0.cancel() }
        listenerTasks.removeAll()

        for action in ShortcutAction.allCases {
            for binding in bindingsByAction[action] ?? [] where binding.enabled {
                let recorderName = binding.recorderName
                let taskID = binding.id

                listenerTasks[taskID] = Task { [weak self] in
                    for await _ in KeyboardShortcuts.events(.keyUp, for: recorderName) {
                        guard !Task.isCancelled else { return }
                        self?.handle(action)
                    }
                }
            }
        }
    }

    func setRecorderActive(_ isActive: Bool) {
        isRecorderActive = isActive
    }

    private func handle(_ action: ShortcutAction) {
        guard !isRecorderActive else { return }
        onAction?(action)
    }
}
