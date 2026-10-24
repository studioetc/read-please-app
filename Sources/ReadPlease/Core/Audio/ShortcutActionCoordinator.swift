import Foundation
import Observation

@Observable
@MainActor
final class ShortcutActionCoordinator {
    static let shared = ShortcutActionCoordinator()

    let screenAreaReader: ScreenAreaReader
    private var lastScreenAreaOutcome: ScreenAreaReadOutcome?
    private var outcomeRevision: UInt = 0
    private(set) var screenAreaOutcome: ScreenAreaReadOutcome? {
        get {
            playbackManager.actionRevision == outcomeRevision ? lastScreenAreaOutcome : nil
        }
        set {
            lastScreenAreaOutcome = newValue
            outcomeRevision = playbackManager.actionRevision
        }
    }
    private var screenAreaTask: Task<Void, Never>?
    private var screenAreaGeneration: UInt = 0

    var isReadingScreenArea: Bool { screenAreaTask != nil }

    private let playbackManager: PlaybackManager
    private let selectedTextProvider: @MainActor () async -> String?
    private var playPauseTask: Task<Void, Never>?
    private var playPauseGeneration: UInt = 0

    init(
        playbackManager: PlaybackManager = .shared,
        screenAreaReader: ScreenAreaReader = ScreenAreaReader(),
        selectedTextProvider: @escaping @MainActor () async -> String? = {
            await TextSelectionService.shared.getSelectedText()
        }
    ) {
        self.playbackManager = playbackManager
        self.screenAreaReader = screenAreaReader
        self.selectedTextProvider = selectedTextProvider
    }

    func handle(_ action: ShortcutAction, source: String = "menu") {
        switch action {
        case .playPause:
            cancelScreenAreaRead()
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

        case .readScreenArea:
            guard screenAreaTask == nil else { return }
            cancelSelectionRead()
            screenAreaOutcome = nil
            screenAreaGeneration &+= 1
            let generation = screenAreaGeneration
            let actionRevision = playbackManager.actionRevision
            let timing = ScreenAreaTiming()
            timing.event("invocation_received", detail: "source=\(source)")
            screenAreaTask = ScreenAreaTiming.$current.withValue(timing) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer {
                        if self.screenAreaGeneration == generation {
                            self.screenAreaTask = nil
                        }
                    }
                    do {
                        let text = try await self.screenAreaReader.readText()
                        guard self.isCurrentScreenAreaRead(generation, revision: actionRevision) else { return }
                        self.playbackManager.play(text: text)
                    } catch {
                        guard self.isCurrentScreenAreaRead(generation, revision: actionRevision) else { return }
                        timing.event("ended_without_playback", detail: "error=\(String(describing: error))")
                        switch error {
                        case is CancellationError, RegionCaptureError.cancelled:
                            break
                        case RegionCaptureError.permissionNeeded:
                            self.screenAreaOutcome = .permissionNeeded
                        case ScreenAreaReadError.notAvailableYet:
                            self.screenAreaOutcome = .notAvailableYet
                        case ScreenAreaReadError.noTextFound:
                            self.screenAreaOutcome = .noTextFound
                        case RegionCaptureError.failed(let detail):
                            self.screenAreaOutcome = .failed(detail)
                        default:
                            self.screenAreaOutcome = .failed(error.localizedDescription)
                        }
                    }
                }
            }

        case .stop:
            cancelSelectionRead()
            cancelScreenAreaRead()
            playbackManager.stop()
        }
    }

    func handleMenuBarPrimaryAction() {
        cancelSelectionRead()
        cancelScreenAreaRead()
        playbackManager.handleMenuBarPrimaryAction()
    }

    private func isCurrentScreenAreaRead(_ generation: UInt, revision: UInt) -> Bool {
        !Task.isCancelled && screenAreaGeneration == generation && playbackManager.actionRevision == revision
    }

    private func cancelSelectionRead() {
        playPauseGeneration &+= 1
        playPauseTask?.cancel()
        playPauseTask = nil
    }

    private func cancelScreenAreaRead() {
        screenAreaGeneration &+= 1
        screenAreaTask?.cancel()
        screenAreaTask = nil
        screenAreaOutcome = nil
    }
}
