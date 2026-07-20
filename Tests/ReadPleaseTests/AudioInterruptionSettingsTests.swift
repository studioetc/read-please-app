import Foundation
import XCTest
@testable import ReadPlease

@MainActor
final class AudioInterruptionSettingsTests: XCTestCase {
    func testDefaultsToOffWithoutStoredPreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AudioInterruptionSettings(defaults: defaults)

        XCTAssertEqual(settings.mode, .off)
    }

    func testMigratesLegacySpikePreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            AudioInterruptionMode.muteAllOtherAudioWhileSpeaking.rawValue,
            forKey: "ReadPlease.audioDuckingMode"
        )

        let settings = AudioInterruptionSettings(defaults: defaults)

        XCTAssertEqual(settings.mode, .muteAllOtherAudioWhileSpeaking)
        XCTAssertEqual(
            defaults.string(forKey: "ReadPlease.audioInterruptionMode"),
            AudioInterruptionMode.muteAllOtherAudioWhileSpeaking.rawValue
        )
    }

    func testPersistsModeChanges() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AudioInterruptionSettings(defaults: defaults)

        settings.mode = .muteChromeWhileSpeaking

        XCTAssertEqual(
            defaults.string(forKey: "ReadPlease.audioInterruptionMode"),
            AudioInterruptionMode.muteChromeWhileSpeaking.rawValue
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AudioInterruptionSettingsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
