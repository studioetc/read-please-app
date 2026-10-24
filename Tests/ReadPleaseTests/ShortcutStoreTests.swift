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

        XCTAssertEqual(firstShortcut["key"] as? String, "backtick")
        XCTAssertEqual(firstShortcut["modifiers"] as? [String], ["control"])
        XCTAssertNil(playPause.first?["id"])
    }

    func testOlderConfigAddsScreenAreaDefaultsAndPersistsWithoutChangingCustomizations() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"version": 2, "actions": {
            "playPause": [{"description": "My custom binding", "shortcut": {"key": "f17", "modifiers": ["option"]}, "source": "custom"}],
            "stop": []
        }}
        """.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        XCTAssertNil(store.banner)
        XCTAssertEqual(store.bindings(for: .playPause).first?.description, "My custom binding")
        XCTAssertEqual(store.bindings(for: .playPause).first?.source, .custom)
        XCTAssertTrue(store.bindings(for: .stop).isEmpty)
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.shortcut), ShortcutAction.readScreenArea.defaultBindings.map(\.shortcut))
        let saved = try ShortcutConfigCodec.decodeFile(from: Data(contentsOf: configURL))
        XCTAssertFalse(saved.needsMigration)
        XCTAssertEqual(saved.bindingsByAction[.playPause]?.first?.shortcut, store.bindings(for: .playPause).first?.shortcut)
        XCTAssertEqual(saved.bindingsByAction[.readScreenArea]?.count, 2)
    }

    func testMigrationOmitsConflictingDefaultAndShowsUsableF16() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"version": 2, "actions": {
            "playPause": [{"shortcut": {"key": "two", "modifiers": ["control"]}, "source": "custom"}], "stop": []
        }}
        """.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        XCTAssertNil(store.banner)
        XCTAssertEqual(store.bindings(for: .playPause).count, 1)
        XCTAssertEqual(store.bindings(for: .playPause).first?.enabled, true)
        let expected = [ShortcutAction.readScreenArea.defaultBindings[1].shortcut]
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.shortcut), expected)
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.enabled), [true])
        let saved = try ShortcutConfigCodec.decodeBindings(from: Data(contentsOf: configURL))
        XCTAssertEqual(saved[.readScreenArea]?.map(\.shortcut), expected)
        XCTAssertEqual(saved[.readScreenArea]?.map(\.enabled), [true])
    }

    func testExplicitlyEmptyScreenAreaBindingsAreNotRestoredOnReload() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version": 2, "actions": {"playPause": [], "stop": [], "readScreenArea": []}}"#.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        XCTAssertNil(store.banner)
        XCTAssertTrue(store.bindings(for: .readScreenArea).isEmpty)
        store.reloadFromDiskManually()
        XCTAssertTrue(store.bindings(for: .readScreenArea).isEmpty)
    }

    func testExistingCustomScreenAreaBindingsSurviveReload() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"f18","modifiers":["option"]},"enabled":false,"source":"custom"}]}}"#.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        XCTAssertNil(store.banner)
        let expected = try XCTUnwrap(store.bindings(for: .readScreenArea).first)
        XCTAssertEqual(expected.source, .custom)
        XCTAssertFalse(expected.enabled)
        store.reloadFromDiskManually()
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.shortcut), [expected.shortcut])
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.enabled), [false])
    }

    func testMigrationLeavesScreenAreaEmptyWhenBothDefaultsConflict() throws {
        let data = Data(#"{"version":2,"actions":{"playPause":[{"shortcut":{"key":"two","modifiers":["control"]}}],"stop":[{"shortcut":{"key":"f16","modifiers":[]}}]}}"#.utf8)
        let decoded = try ShortcutConfigCodec.decodeBindings(from: data)
        XCTAssertEqual(decoded[.readScreenArea], [])
        XCTAssertEqual(decoded[.playPause]?.count, 1)
        XCTAssertEqual(decoded[.stop]?.count, 1)
    }

    func testRecorderReenablesDisabledBindingForSameOrDifferentKey() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"f18","modifiers":[]},"enabled":false,"source":"default"}]}}"#.utf8)
        for useSameKey in [true, false] {
            try data.write(to: configURL, options: .atomic)
            let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                      syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
            let existing = try XCTUnwrap(store.bindings(for: .readScreenArea).first)
            let shortcut = useSameKey ? existing.shortcut : ShortcutAction.readScreenArea.defaultBindings[1].shortcut
            store.updateBinding(id: existing.id, in: .readScreenArea, shortcut: shortcut)
            XCTAssertNil(store.banner)
            XCTAssertEqual(store.bindings(for: .readScreenArea).first?.shortcut, shortcut)
            XCTAssertEqual(store.bindings(for: .readScreenArea).first?.enabled, true)
            XCTAssertEqual(store.bindings(for: .readScreenArea).first?.source, .custom)
            let saved = try ShortcutConfigCodec.decodeBindings(from: Data(contentsOf: configURL))
            XCTAssertEqual(saved[.readScreenArea]?.first?.enabled, true)
        }
    }

    func testDisabledBindingsSurviveLaunchAndReloadInPathWithSpaces() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReadPlease config \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appending(path: "shortcuts.json")
        let data = Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"two","modifiers":["control"]},"enabled":false,"source":"default"},{"shortcut":{"key":"f16","modifiers":[]},"enabled":true,"source":"default"}]}}"#.utf8)
        try data.write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        XCTAssertNil(store.banner)
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.enabled), [false, true])
        store.reloadFromDiskManually()
        XCTAssertEqual(store.bindings(for: .readScreenArea).map(\.enabled), [false, true])
        XCTAssertEqual(try Data(contentsOf: configURL), data)
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
