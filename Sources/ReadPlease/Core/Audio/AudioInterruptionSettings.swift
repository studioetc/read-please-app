import Foundation

enum AudioInterruptionMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case muteChromeWhileSpeaking
    case muteAllOtherAudioWhileSpeaking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .muteChromeWhileSpeaking:
            "Mute Chrome while speaking"
        case .muteAllOtherAudioWhileSpeaking:
            "Mute all other audio while speaking"
        }
    }
}

@Observable
@MainActor
final class AudioInterruptionSettings {
    static let shared = AudioInterruptionSettings()

    private enum DefaultsKey {
        static let mode = "ReadPlease.audioInterruptionMode"
        static let legacyMode = "ReadPlease.audioDuckingMode"
    }

    private let defaults: UserDefaults

    var mode: AudioInterruptionMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: DefaultsKey.mode)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMode = defaults.string(forKey: DefaultsKey.mode)
            ?? defaults.string(forKey: DefaultsKey.legacyMode)
        self.mode = storedMode.flatMap(AudioInterruptionMode.init(rawValue:)) ?? .off

        if defaults.string(forKey: DefaultsKey.mode) == nil, storedMode != nil {
            defaults.set(mode.rawValue, forKey: DefaultsKey.mode)
        }
    }
}
