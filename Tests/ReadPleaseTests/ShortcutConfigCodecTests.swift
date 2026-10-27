import Carbon.HIToolbox
import KeyboardShortcuts
import Foundation
import Testing
@testable import ReadPlease

@Suite final class ShortcutConfigCodecTests {
    @Test func testDecodeReadableV2ShortcutWithOptionalDescriptionAndMultipleModifiers() throws {
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
        let binding = try #require(bindings[.playPause]?.first)

        #expect(binding.description == "Browser fallback")
        #expect(binding.shortcut.carbonKeyCode == Int(kVK_ANSI_Backslash))
        #expect(binding.shortcut.carbonModifiers == (ShortcutModifier.normalizeCarbonModifiers(Int(optionKey) | Int(shiftKey))))
        #expect(binding.source == .custom)
    }

    @Test func testDecodeLegacyV1ShortcutAndEncodeBackToReadableV2() throws {
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
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect((object["version"] as? Int) == 2)

        let actions = try #require(object["actions"] as? [String: Any])
        let stop = try #require(actions["stop"] as? [[String: Any]])
        let binding = try #require(stop.first)
        let shortcut = try #require(binding["shortcut"] as? [String: Any])

        #expect((shortcut["key"] as? String) == "delete")
        #expect((shortcut["modifiers"] as? [String]) == (["option"]))
        #expect((binding["id"]) == nil)
    }

    @Test func testLegacyMigrationAddsScreenAreaDefaults() throws {
        let decoded = try ShortcutConfigCodec.decodeFile(from: Data(#"{"version":1,"actions":{"stop":[]}}"#.utf8))
        #expect(decoded.needsMigration)
        #expect((decoded.bindingsByAction[.readScreenArea]?.map(\.shortcut)) == ShortcutAction.readScreenArea.defaultBindings.map(\.shortcut))
        #expect((decoded.bindingsByAction[.readScreenArea]?.map(\.enabled)) == ([true, true]))
        #expect((decoded.bindingsByAction[.stop]) == ([]))
    }

    @Test func testEncodeOmitsEmptyDescription() throws {
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
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try #require(object["actions"] as? [String: Any])
        let playPause = try #require(actions["playPause"] as? [[String: Any]])

        #expect((playPause.first?["description"]) == nil)
    }

    @Test func testDecodeRejectsUnknownKeyName() {
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

        let error = #expect(throws: (any Error).self) { try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8)) }
        #expect(error?.localizedDescription.contains("Unknown shortcut key") == true)
    }

    @Test func testDecodeRejectsUnknownModifierName() {
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

        let error = #expect(throws: (any Error).self) { try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8)) }
        #expect(error?.localizedDescription.contains("Unknown shortcut modifier") == true)
    }

    @Test func testDecodeRejectsMalformedShortcutObjectWithReadableError() {
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

        let error = #expect(throws: (any Error).self) { try ShortcutConfigCodec.decodeBindings(from: Data(json.utf8)) }
        #expect(error?.localizedDescription.contains("Couldn't read shortcuts.json") == true)
    }
}
