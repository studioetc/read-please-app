import Foundation

@MainActor
final class ShortcutActionCoordinator {
    private let playbackManager: PlaybackManager
    private let selectedTextProvider: @MainActor () async -> String?
    private var playPauseTask: Task<Void, Never>?
    private var playPauseGeneration: UInt = 0

    init(
        playbackManager: PlaybackManager = .shared,
        selectedTextProvider: @escaping @MainActor () async -> String? = {
            await TextSelectionService.shared.getSelectedText()
        }
    ) {
        self.playbackManager = playbackManager
        self.selectedTextProvider = selectedTextProvider
    }

    func handle(_ action: ShortcutAction) {
        switch action {
        case .playPause:
            guard playPauseTask == nil else {
                print("ShortcutActionCoordinator: Ignoring Play / Pause while selection is pending.")
                return
            }

            playPauseGeneration &+= 1
            let generation = playPauseGeneration
            playPauseTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.playPauseGeneration == generation {
                        self.playPauseTask = nil
                    }
                }

                let actionRevision = self.playbackManager.actionRevision
                let selectedText = await self.selectedTextProvider()
                guard
                    !Task.isCancelled,
                    self.playbackManager.actionRevision == actionRevision
                else { return }
                self.playbackManager.handleShortcutPlayPause(selectedText: selectedText)
            }

        case .stop:
            playPauseGeneration &+= 1
            playPauseTask?.cancel()
            playPauseTask = nil
            playbackManager.stop()
        }
    }
}
