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

    // Dependencies
    private let textSelectionService = TextSelectionService.shared
    private var activeEngine: TTSEngine

    public init(engine: TTSEngine? = nil) {
        let resolvedEngine = engine ?? SystemTTSEngine()
        let defaults = UserDefaults.standard

        self.activeEngine = resolvedEngine
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
            Task { @MainActor in
                self?.handleEngineStateChange(newState)
            }
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
    public func togglePlayPause() {
        if state == .playing {
            pause()
        } else if state == .paused {
            resume()
        } else {
            playSelection()
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
            play(text: text)
        }
    }

    @MainActor
    public func playSelection() {
        guard let text = textSelectionService.getSelectedText() else {
            print("No text selected")
            setStatusMessage("No selected text found.")
            return
        }
        play(text: text)
    }

    @MainActor
    public func play(text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            setStatusMessage("Text is empty.")
            return
        }

        clearStatusMessage()
        print("PlaybackManager: play(text:) called with \(trimmedText.count) characters")

        if state != .stopped {
            activeEngine.stop()
        }

        currentText = trimmedText
        let options = SpeechOptions(rate: currentRate, voiceId: currentVoiceId)
        print(
            "PlaybackManager: Calling engine.speak with rate=\(currentRate) voice=\(currentVoiceId ?? "nil")"
        )
        activeEngine.speak(text: trimmedText, options: options)
    }

    @MainActor
    public func pause() {
        clearStatusMessage()
        activeEngine.pause()
    }

    @MainActor
    public func resume() {
        clearStatusMessage()
        activeEngine.resume()
    }

    @MainActor
    public func stop() {
        clearStatusMessage()
        activeEngine.stop()
        currentText = nil
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
