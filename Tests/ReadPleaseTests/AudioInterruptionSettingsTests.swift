import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class AudioInterruptionSettingsTests {
    @Test func testDefaultsToOffWithoutStoredPreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AudioInterruptionSettings(defaults: defaults)

        #expect(settings.mode == .off)
    }

    @Test func testMigratesLegacySpikePreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AudioInterruptionMode.muteAllOtherAudioWhileSpeaking.rawValue,
            forKey: "ReadPlease.audioDuckingMode"
        )

        let settings = AudioInterruptionSettings(defaults: defaults)

        #expect(settings.mode == .muteAllOtherAudioWhileSpeaking)
        #expect(defaults.string(forKey: "ReadPlease.audioInterruptionMode") == AudioInterruptionMode.muteAllOtherAudioWhileSpeaking.rawValue)
    }

    @Test func testPersistsModeChanges() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AudioInterruptionSettings(defaults: defaults)

        settings.mode = .muteChromeWhileSpeaking

        #expect(defaults.string(forKey: "ReadPlease.audioInterruptionMode") == AudioInterruptionMode.muteChromeWhileSpeaking.rawValue)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AudioInterruptionSettingsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
