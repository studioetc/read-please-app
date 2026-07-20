import AVFoundation
import Foundation

public enum VoiceQuality: Sendable {
    case standard
    case enhanced
    case premium
}

public struct Voice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let locale: Locale
    public let quality: VoiceQuality

    public init(id: String, name: String, locale: Locale, quality: VoiceQuality) {
        self.id = id
        self.name = name
        self.locale = locale
        self.quality = quality
    }
}

public struct SpeechOptions: Sendable {
    public let rate: Float
    public let pitch: Float
    public let volume: Float
    public let voiceId: String?

    public init(rate: Float = 1.0, pitch: Float = 1.0, volume: Float = 1.0, voiceId: String? = nil)
    {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.voiceId = voiceId
    }
}

public enum TTSEngineState: Sendable {
    case stopped
    case playing
    case paused
}

@MainActor
public protocol TTSEngine: AnyObject {
    var id: String { get }
    var availableVoices: [Voice] { get }
    var state: TTSEngineState { get }
    var onStateChange: ((TTSEngineState) -> Void)? { get set }

    func speak(text: String, options: SpeechOptions)
    func stop()
    func pause()
    func resume()
}
