import Carbon.HIToolbox
import KeyboardShortcuts
import XCTest
@testable import ReadPlease

final class ShortcutConfigCodecTests: XCTestCase {
    func testDecodeReadableV2ShortcutWithOptionalDescriptionAndMultipleModifiers() throws {
        let json = """
        {
          "version": 2,
          "actions": {
            "playPause": [
              {
                "description": "  Browser fallback  ",
                "enabled": true,
                "shortcut": {
                  "key": "backslash",
                  "modifiers": ["option", "shift"]
                },
                "source": "custom"
              }
            ]
          }
        }
        """

        let bindings = try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8))
        let binding = try XCTUnwrap(bindings[.playPause]?.first)

        XCTAssertEqual(binding.description, "Browser fallback")
        XCTAssertEqual(binding.shortcut.carbonKeyCode, Int(kVK_ANSI_Backslash))
        XCTAssertEqual(
            binding.shortcut.carbonModifiers,
            ShortcutModifier.normalizeCarbonModifiers(Int(optionKey) | Int(shiftKey))
        )
        XCTAssertEqual(binding.source, .custom)
    }

    func testDecodeLegacyV1ShortcutAndEncodeBackToReadableV2() throws {
        let legacyJSON = """
        {
          "version": 1,
          "actions": {
            "stop": [
              {
                "enabled": true,
                "shortcut": {
                  "carbonKeyCode": \(Int(kVK_Delete)),
                  "carbonModifiers": \(Int(optionKey))
                },
                "source": "default"
              }
            ]
          }
        }
        """

        let bindings = try ShortcutConfigCodec.decodeBindings(from: Data(legacyJSON.utf8))
        let encoded = try ShortcutConfigCodec.encodeFile(bindings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 2)

        let actions = try XCTUnwrap(object["actions"] as? [String: Any])
        let stop = try XCTUnwrap(actions["stop"] as? [[String: Any]])
        let binding = try XCTUnwrap(stop.first)
        let shortcut = try XCTUnwrap(binding["shortcut"] as? [String: Any])

        XCTAssertEqual(shortcut["key"] as? String, "delete")
        XCTAssertEqual(shortcut["modifiers"] as? [String], ["option"])
        XCTAssertNil(binding["id"])
    }

    func testEncodeOmitsEmptyDescription() throws {
        let bindings: [ShortcutAction: [ShortcutBinding]] = [
            .playPause: [
                ShortcutBinding(
                    id: UUID().uuidString,
                    description: "   ",
                    shortcut: KeyboardShortcuts.Shortcut(carbonKeyCode: Int(kVK_F14)),
                    enabled: true,
                    source: .defaultValue
                )
            ]
        ]

        let encoded = try ShortcutConfigCodec.encodeFile(bindings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [String: Any])
        let playPause = try XCTUnwrap(actions["playPause"] as? [[String: Any]])

        XCTAssertNil(playPause.first?["description"])
    }

    func testDecodeRejectsUnknownKeyName() {
        let json = """
        {
          "version": 2,
          "actions": {
            "playPause": [
              {
                "shortcut": {
                  "key": "totallyNotAKey",
                  "modifiers": []
                }
              }
            ]
          }
        }
        """

        XCTAssertThrowsError(try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unknown shortcut key"))
        }
    }

    func testDecodeRejectsUnknownModifierName() {
        let json = """
        {
          "version": 2,
          "actions": {
            "playPause": [
              {
                "shortcut": {
                  "key": "f14",
                  "modifiers": ["hyper"]
                }
              }
            ]
          }
        }
        """

        XCTAssertThrowsError(try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unknown shortcut modifier"))
        }
    }

    func testDecodeRejectsMalformedShortcutObjectWithReadableError() {
        let json = """
        {
          "version": 2,
          "actions": {
            "playPause": [
              {
                "enabled": true
              }
            ]
          }
        }
        """

        XCTAssertThrowsError(try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Couldn't read shortcuts.json"))
        }
    }
}
