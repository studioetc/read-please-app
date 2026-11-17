import AVFoundation
import Foundation
import SwiftUI

@Observable
@MainActor
public class PlaybackManager {
    public static let shared = PlaybackManager()
    private enum DefaultsKey {
        static let rate = "ReadPlease.currentRate"
        static let voiceID = "ReadPlease.currentVoiceId"
    }

    private static let previewSample = "Read Please reads your selected text aloud."

    public private(set) var state: TTSEngineState
    public var currentRate: Float {
        didSet {
            guard currentRate != oldValue else { return }
            UserDefaults.standard.set(Double(currentRate), forKey: DefaultsKey.rate)
        }
    }
    public var currentVoiceId: String? {
        didSet {
            guard currentVoiceId != oldValue else { return }
            if let currentVoiceId {
                UserDefaults.standard.set(currentVoiceId, forKey: DefaultsKey.voiceID)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.voiceID)
            }
        }
    }
    public private(set) var currentText: String?
    public private(set) var statusMessage: String?
    private(set) var actionRevision: UInt = 0

    // Dependencies
    private let textSelectionService = TextSelectionService.shared
    private let audioMuteController: any AudioMuting
    private let audioInterruptionMode: @MainActor () -> AudioInterruptionMode
    private let audioMuteRetryDelay: Duration
    private var activeEngine: TTSEngine
    private var activeAudioInterruptionMode: AudioInterruptionMode?
    private var audioMuteGeneration: UInt = 0
    private var audioMuteStartTask: Task<Void, Never>?
    private var pendingAudioInterruptionMode: AudioInterruptionMode?
    private var audioMuteRetryTask: Task<Void, Never>?
    private var audioMuteStartWasAttempted = false

    public convenience init(engine: TTSEngine? = nil) {
        self.init(
            engine: engine,
            audioMuteController: AudioMuteController.shared,
            audioInterruptionMode: { AudioInterruptionSettings.shared.mode },
            audioMuteRetryDelay: .milliseconds(150)
        )
    }

    init(
        engine: TTSEngine?,
        audioMuteController: any AudioMuting,
        audioInterruptionMode: @escaping @MainActor () -> AudioInterruptionMode,
        audioMuteRetryDelay: Duration = .milliseconds(150)
    ) {
        let resolvedEngine = engine ?? SystemTTSEngine()
        let defaults = UserDefaults.standard

        self.activeEngine = resolvedEngine
        self.audioMuteController = audioMuteController
        self.audioInterruptionMode = audioInterruptionMode
        self.audioMuteRetryDelay = audioMuteRetryDelay
        self.activeAudioInterruptionMode = nil
        self.audioMuteRetryTask = nil
        if defaults.object(forKey: DefaultsKey.rate) != nil {
            self.currentRate = defaults.float(forKey: DefaultsKey.rate)
        } else {
            self.currentRate = 1.25
        }
        self.currentVoiceId = Self.resolveInitialVoiceID(engine: resolvedEngine)
        self.state = resolvedEngine.state
        self.currentText = nil
        self.statusMessage = nil

        self.activeEngine.onStateChange = { [weak self] newState in
            self?.handleEngineStateChange(newState)
        }
    }

    public var availableVoices: [Voice] {
        activeEngine.availableVoices
    }

    // Canonical Vocalizer voice name per English region, used to pick a sensible
    // default voice when the user hasn't chosen one yet.
    private static let canonicalVoiceNamesByRegion: [String: String] = [
        "en-US": "Samantha",
        "en-GB": "Daniel",
        "en-AU": "Karen",
        "en-IE": "Moira",
        "en-IN": "Rishi",
        "en-ZA": "Tessa",
    ]

    private static func resolveInitialVoiceID(engine: TTSEngine) -> String? {
        let defaults = UserDefaults.standard
        let voices = engine.availableVoices

        if let storedVoiceID = defaults.string(forKey: DefaultsKey.voiceID),
            voices.contains(where: { $0.id == storedVoiceID })
        {
            return storedVoiceID
        }

        let languageCode = AVSpeechSynthesisVoice.currentLanguageCode()

        // Prefer the region's canonical Vocalizer voice at the highest installed quality.
        // If currentLanguageCode() returns a bare language with no region (e.g. "en"), there is no
        // canonical-name entry, so this lookup is skipped and we fall through to the compact fallback.
        if let canonicalName = canonicalVoiceNamesByRegion[languageCode] {
            let canonicalMatches = voices.filter { voice in
                voice.id.hasPrefix("com.apple.voice.") && voice.name == canonicalName
            }
            if let best = canonicalMatches.max(by: { qualityRank($0.quality) < qualityRank($1.quality) }) {
                return best.id
            }
        }

        // Fall back to a compact Vocalizer matching the current language.
        // Normalize the locale identifier (e.g. "en_US") to match currentLanguageCode() ("en-US").
        if let localeMatch = voices.first(where: { voice in
            voice.id.hasPrefix("com.apple.voice.compact.")
                && voice.locale.identifier.replacingOccurrences(of: "_", with: "-")
                    .hasPrefix(languageCode)
        }) {
            return localeMatch.id
        }

        // No canonical accent and no language match — hand off to the OS system default voice
        // (nil) rather than picking an arbitrary, likely wrong-language compact.
        return nil
    }

    private static func qualityRank(_ quality: VoiceQuality) -> Int {
        switch quality {
        case .standard:
            return 0
        case .enhanced:
            return 1
        case .premium:
            return 2
        }
    }

    private func handleEngineStateChange(_ newState: TTSEngineState) {
        state = newState
        switch newState {
        case .playing:
            startAudioInterruptionIfNeeded()
        case .paused, .stopped:
            endAudioInterruption()
        }

        if newState == .stopped {
            currentText = nil
        }
    }

    private func clearStatusMessage() {
        statusMessage = nil
    }

    private func setStatusMessage(_ message: String) {
        statusMessage = message
    }

    @MainActor
    public func togglePlayPause() async {
        if state == .playing {
            pause()
        } else if state == .paused {
            resume()
        } else {
            await playSelection()
        }
    }

    @MainActor
    public func handleMenuBarPrimaryAction() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .stopped:
            guard let text = textSelectionService.getSelectedTextFromLastActiveAppViaAccessibility(),
                !text.isEmpty
            else {
                setStatusMessage("Couldn't read selected text here. Try F14 in the source app.")
                return
            }
            ScreenAreaTiming.selectionText(text)
            play(text: text)
        }
    }

    @MainActor
    public func playSelection() async {
        let startingRevision = actionRevision
        let selectedText = await textSelectionService.getSelectedText()
        guard !Task.isCancelled, actionRevision == startingRevision else { return }
        handleShortcutPlayPause(selectedText: selectedText)
    }

    func handleShortcutPlayPause(selectedText: String?) {
        // Compare trimmed text: `play` stores `currentText` trimmed, and selections often end in a
        // newline (e.g. a triple-clicked paragraph), which would otherwise restart instead of pausing.
        let trimmedSelection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSelection = trimmedSelection?.isEmpty == false

        if state == .stopped {
            guard hasSelection, let selectedText else {
                print("No text selected")
                setStatusMessage("No selected text found.")
                return
            }
            ScreenAreaTiming.selectionText(selectedText)
            play(text: selectedText)
            return
        }

        if hasSelection, let selectedText, trimmedSelection != currentText {
            ScreenAreaTiming.selectionText(selectedText)
            play(text: selectedText)
            return
        }

        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .stopped:
            // Handled above.
            break
        }
    }

    @MainActor
    public func play(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            setStatusMessage("Text is empty.")
            return
        }

        clearStatusMessage()
        actionRevision &+= 1
        print("PlaybackManager: play(text:) called with \(trimmedText.count) characters")

        currentText = trimmedText
        let options = SpeechOptions(rate: currentRate, voiceId: currentVoiceId)
        print(
            "PlaybackManager: Calling engine.speak with rate=\(currentRate) voice=\(currentVoiceId ?? "nil")"
        )
        startAudioInterruptionIfNeeded()
        ScreenAreaTiming.current?.event("playback_requested", detail: "owner=PlaybackManager chars=\(trimmedText.count)")
        activeEngine.speak(text: trimmedText, options: options)
        ScreenAreaTiming.current?.event("playback_command_returned")
    }

    @MainActor
    public func pause() {
        clearStatusMessage()
        actionRevision &+= 1
        endAudioInterruption()
        activeEngine.pause()
    }

    @MainActor
    public func resume() {
        clearStatusMessage()
        actionRevision &+= 1
        activeEngine.resume()
    }

    @MainActor
    public func stop() {
        clearStatusMessage()
        actionRevision &+= 1
        endAudioInterruption()
        activeEngine.stop()
        currentText = nil
    }

    func audioInterruptionModeDidChange() {
        endAudioInterruption()
        if state == .playing {
            startAudioInterruptionIfNeeded()
        }
    }

    private func startAudioInterruptionIfNeeded() {
        let mode = audioInterruptionMode()
        guard mode != .off else {
            endAudioInterruption()
            return
        }
        guard activeAudioInterruptionMode != mode, pendingAudioInterruptionMode != mode else { return }

        audioMuteRetryTask?.cancel()
        audioMuteRetryTask = nil
        audioMuteStartTask?.cancel()
        pendingAudioInterruptionMode = mode
        audioMuteStartWasAttempted = true
        let generation = audioMuteGeneration
        audioMuteStartTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let started = await self.audioMuteController.start(mode: mode)
            guard !Task.isCancelled, self.audioMuteGeneration == generation,
                  self.state == .playing, self.audioInterruptionMode() == mode else { return }
            self.pendingAudioInterruptionMode = nil
            self.audioMuteStartTask = nil
            if started {
                self.activeAudioInterruptionMode = mode
                return
            }
            self.audioMuteRetryTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: self.audioMuteRetryDelay) }
                catch { return }
                guard !Task.isCancelled, self.audioMuteGeneration == generation,
                      self.state == .playing, self.audioInterruptionMode() == mode else { return }
                let retried = await self.audioMuteController.start(mode: mode)
                guard !Task.isCancelled, self.audioMuteGeneration == generation,
                      self.state == .playing, self.audioInterruptionMode() == mode else { return }
                if retried { self.activeAudioInterruptionMode = mode }
                else { self.setStatusMessage(self.audioInterruptionFailureMessage(for: mode)) }
            }
        }
    }

    private func endAudioInterruption() {
        audioMuteGeneration &+= 1
        audioMuteStartTask?.cancel()
        audioMuteStartTask = nil
        pendingAudioInterruptionMode = nil
        audioMuteRetryTask?.cancel()
        audioMuteRetryTask = nil

        if activeAudioInterruptionMode != nil || audioMuteStartWasAttempted {
            audioMuteController.stop()
        }
        activeAudioInterruptionMode = nil
        audioMuteStartWasAttempted = false
    }

    private func audioInterruptionFailureMessage(for mode: AudioInterruptionMode) -> String {
        switch mode {
        case .off:
            return ""
        case .muteChromeWhileSpeaking:
            return "Reading started, but Chrome audio couldn't be muted."
        case .muteAllOtherAudioWhileSpeaking:
            return "Reading started, but other audio couldn't be muted."
        }
    }

    @MainActor
    public func previewVoice() {
        play(text: Self.previewSample)
    }

    public func setRate(_ rate: Float) {
        currentRate = rate
    }

    public func setVoice(_ voiceId: String?) {
        currentVoiceId = voiceId
    }
}
