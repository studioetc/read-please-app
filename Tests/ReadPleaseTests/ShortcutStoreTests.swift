import XCTest
@testable import ReadPlease

@MainActor
final class ShortcutStoreTests: XCTestCase {
    func testStoreCreatesReadableV2Defaults() throws {
        let configURL = makeTemporaryConfigURL()
        let store = ShortcutStore(
            configFileURL: configURL,
            registerBindingsOnChanges: false,
            syncRecorderStorageOnChanges: false,
            purgeKeyboardShortcutsOnInit: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path()))
        XCTAssertEqual(store.bindings(for: .playPause).count, 2)

        let object = try loadJSONObject(from: configURL)
        XCTAssertEqual(object["version"] as? Int, 2)
    }

    func testManualReloadKeepsExistingBindingsWhenFileIsInvalid() throws {
        let configURL = makeTemporaryConfigURL()
        let store = ShortcutStore(
            configFileURL: configURL,
            registerBindingsOnChanges: false,
            syncRecorderStorageOnChanges: false,
            purgeKeyboardShortcutsOnInit: false
        )
        let originalBindings = store.bindings(for: .playPause)

        let invalidJSON = """
        {
          "version": 2,
          "actions": {
            "playPause": [
              {
                "shortcut": {
                  "key": "f14",
                  "modifiers": []
                }
              }
            ],
            "stop": [
              {
                "shortcut": {
                  "key": "f14",
                  "modifiers": []
                }
              }
            ]
          }
        }
        """

        try Data(invalidJSON.utf8).write(to: configURL, options: .atomic)
        store.reloadFromDiskManually()

        XCTAssertEqual(store.bindings(for: .playPause), originalBindings)
        XCTAssertEqual(store.banner?.tone, .error)
        XCTAssertTrue(store.banner?.text.contains("assigned more than once") == true)
    }

    func testResetAllWritesReadableDefaults() throws {
        let configURL = makeTemporaryConfigURL()
        let store = ShortcutStore(
            configFileURL: configURL,
            registerBindingsOnChanges: false,
            syncRecorderStorageOnChanges: false,
            purgeKeyboardShortcutsOnInit: false
        )

        try Data(
            """
            {
              "version": 2,
              "actions": {
                "playPause": [],
                "stop": []
              }
            }
            """.utf8
        ).write(to: configURL, options: .atomic)

        store.resetAll()

        let object = try loadJSONObject(from: configURL)
        let actions = try XCTUnwrap(object["actions"] as? [String: Any])
        let playPause = try XCTUnwrap(actions["playPause"] as? [[String: Any]])
        let firstShortcut = try XCTUnwrap(playPause.first?["shortcut"] as? [String: Any])

        XCTAssertEqual(firstShortcut["key"] as? String, "f14")
        XCTAssertNil(playPause.first?["id"])
    }

    private func makeTemporaryConfigURL() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return root.appendingPathComponent("shortcuts.json")
    }

    private func loadJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

