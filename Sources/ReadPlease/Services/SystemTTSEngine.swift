import AVFoundation
import Foundation

@MainActor
public class SystemTTSEngine: NSObject, TTSEngine, @preconcurrency AVSpeechSynthesizerDelegate {
    public let id = "system"
    private let synthesizer = AVSpeechSynthesizer()
    private let pronunciationStore = PronunciationStore.shared
    private var pronunciationRules: PronunciationRuleSet { pronunciationStore.ruleSet }
    private var screenAreaTiming: ScreenAreaTiming?
    private var activeUtterance: AVSpeechUtterance?
    public var onStateChange: ((TTSEngineState) -> Void)?
    public private(set) var state: TTSEngineState = .stopped {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    public var availableVoices: [Voice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            Voice(
                id: voice.identifier,
                name: voice.name,
                locale: Locale(identifier: voice.language),
                quality: Self.mapQuality(voice.quality)
            )
        }
    }

    private static func mapQuality(_ quality: AVSpeechSynthesisVoiceQuality) -> VoiceQuality {
        switch quality {
        case .premium:
            return .premium
        case .enhanced:
            return .enhanced
        default:
            return .standard
        }
    }

    public func speak(text: String, options: SpeechOptions) {
        print(
            "SystemTTSEngine: Speaking \(text.count) characters rate=\(options.rate) voice=\(options.voiceId ?? "default")"
        )

        screenAreaTiming = ScreenAreaTiming.current
        let utterance = makeUtterance(for: text)

        // Map rate: Our UI uses 0.5x-2.0x. AVSpeechUtterance uses 0.0-1.0 where ~0.5 is normal.
        // Formula: (userRate - 0.5) / 1.5 maps 0.5->0.0, 1.0->0.33, 2.0->1.0
        // Simpler: use AVSpeechUtteranceDefaultSpeechRate * userRate
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * options.rate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume

        if let voiceId = options.voiceId {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
            print("SystemTTSEngine: Using voice identifier: \(voiceId)")
        } else {
            print("SystemTTSEngine: Using system default voice")
        }

        // Mark the replacement first so a delayed cancellation callback from the previous
        // utterance cannot stop or clear the new playback session.
        activeUtterance = utterance

        // Stop current if any. AVSpeechSynthesizer otherwise queues the new utterance.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        synthesizer.speak(utterance)
        state = .playing
        print("SystemTTSEngine: Speak command issued")
    }

    private func makeUtterance(for text: String) -> AVSpeechUtterance {
        let ruleSet = pronunciationRules
        let ipaTerms = Set(ruleSet.ipaRules.map(\.term))
        let replacementRules = ruleSet.rules.filter { !ipaTerms.contains($0.term) }
        let replacedText = applyReplacementRules(replacementRules, to: text)

        if let attributedText = applyIPARules(ruleSet.ipaRules, to: replacedText) {
            return AVSpeechUtterance(attributedString: attributedText)
        }

        return AVSpeechUtterance(string: replacedText)
    }

    private func applyReplacementRules(_ rules: [PronunciationRule], to text: String) -> String {
        guard !rules.isEmpty else { return text }

        let mutableText = NSMutableString(string: text)

        for rule in rules {
            guard !rule.term.isEmpty, let regex = makeWholeWordRegex(for: rule.term) else { continue }

            regex.replaceMatches(
                in: mutableText,
                options: [],
                range: NSRange(location: 0, length: mutableText.length),
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.value)
            )
        }

        return mutableText as String
    }

    private func applyIPARules(_ rules: [IPARule], to text: String) -> NSAttributedString? {
        guard !rules.isEmpty else { return nil }

        let attributedText = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let ipaAttributeKey = NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute)
        var hasIPAMatches = false

        for rule in rules {
            guard !rule.term.isEmpty, let regex = makeWholeWordRegex(for: rule.term) else { continue }
            let matches = regex.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { continue }

            for match in matches {
                attributedText.addAttribute(ipaAttributeKey, value: rule.ipa, range: match.range)
            }
            hasIPAMatches = true
        }

        return hasIPAMatches ? attributedText : nil
    }

    private func makeWholeWordRegex(for term: String) -> NSRegularExpression? {
        let escapedTerm = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?<![\\p{L}\\p{N}_])\(escapedTerm)(?![\\p{L}\\p{N}_])"
        return try? NSRegularExpression(pattern: pattern)
    }

    public func stop() {
        activeUtterance = nil
        screenAreaTiming = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
    }

    public func pause() {
        if synthesizer.pauseSpeaking(at: .immediate) {
            state = .paused
        }
    }

    public func resume() {
        if synthesizer.continueSpeaking() {
            state = .playing
        }
    }

    // MARK: - Delegate
    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance else { return }
        screenAreaTiming?.event("playback_started", detail: "callback=AVSpeechSynthesizer.didStart")
        state = .playing
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        state = .stopped
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        state = .stopped
    }
}
