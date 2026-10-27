import Foundation
import Testing
@testable import ReadPlease

@MainActor
@Suite final class ShortcutStoreTests {
    @Test func testStoreCreatesReadableV2Defaults() throws {
        let configURL = makeTemporaryConfigURL()
        let store = ShortcutStore(
            configFileURL: configURL,
            registerBindingsOnChanges: false,
            syncRecorderStorageOnChanges: false,
            purgeKeyboardShortcutsOnInit: false
        )

        #expect(FileManager.default.fileExists(atPath: configURL.path()))
        #expect(store.bindings(for: .playPause).count == 2)

        let object = try loadJSONObject(from: configURL)
        #expect((object["version"] as? Int) == 2)
    }

    @Test func testManualReloadKeepsExistingBindingsWhenFileIsInvalid() throws {
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

        #expect(store.bindings(for: .playPause) == originalBindings)
        #expect((store.banner?.tone) == .error)
        #expect(store.banner?.text.contains("assigned more than once") == true)
    }

    @Test func testResetAllWritesReadableDefaults() throws {
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
        let actions = try #require(object["actions"] as? [String: Any])
        let playPause = try #require(actions["playPause"] as? [[String: Any]])
        let firstShortcut = try #require(playPause.first?["shortcut"] as? [String: Any])

        #expect((firstShortcut["key"] as? String) == "backtick")
        #expect((firstShortcut["modifiers"] as? [String]) == (["control"]))
        #expect((playPause.first?["id"]) == nil)
    }

    @Test func testOlderConfigAddsScreenAreaDefaultsAndPersistsWithoutChangingCustomizations() throws {
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
        #expect(store.banner == nil)
        #expect((store.bindings(for: .playPause).first?.description) == "My custom binding")
        #expect((store.bindings(for: .playPause).first?.source) == .custom)
        #expect(store.bindings(for: .stop).isEmpty)
        #expect(store.bindings(for: .readScreenArea).map(\.shortcut) == ShortcutAction.readScreenArea.defaultBindings.map(\.shortcut))
        let saved = try ShortcutConfigCodec.decodeFile(from: Data(contentsOf: configURL))
        #expect(!saved.needsMigration)
        #expect((saved.bindingsByAction[.playPause]?.first?.shortcut) == (store.bindings(for: .playPause).first?.shortcut))
        #expect((saved.bindingsByAction[.readScreenArea]?.count) == 2)
    }

    @Test func testMigrationOmitsConflictingDefaultAndShowsUsableF16() throws {
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
        #expect(store.banner == nil)
        #expect(store.bindings(for: .playPause).count == 1)
        #expect((store.bindings(for: .playPause).first?.enabled) == true)
        let expected = [ShortcutAction.readScreenArea.defaultBindings[1].shortcut]
        #expect(store.bindings(for: .readScreenArea).map(\.shortcut) == expected)
        #expect(store.bindings(for: .readScreenArea).map(\.enabled) == ([true]))
        let saved = try ShortcutConfigCodec.decodeBindings(from: Data(contentsOf: configURL))
        #expect((saved[.readScreenArea]?.map(\.shortcut)) == expected)
        #expect((saved[.readScreenArea]?.map(\.enabled)) == ([true]))
    }

    @Test func testExplicitlyEmptyScreenAreaBindingsAreNotRestoredOnReload() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version": 2, "actions": {"playPause": [], "stop": [], "readScreenArea": []}}"#.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        #expect(store.banner == nil)
        #expect(store.bindings(for: .readScreenArea).isEmpty)
        store.reloadFromDiskManually()
        #expect(store.bindings(for: .readScreenArea).isEmpty)
    }

    @Test func testExistingCustomScreenAreaBindingsSurviveReload() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"f18","modifiers":["option"]},"enabled":false,"source":"custom"}]}}"#.utf8).write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        #expect(store.banner == nil)
        let expected = try #require(store.bindings(for: .readScreenArea).first)
        #expect(expected.source == .custom)
        #expect(!expected.enabled)
        store.reloadFromDiskManually()
        #expect(store.bindings(for: .readScreenArea).map(\.shortcut) == ([expected.shortcut]))
        #expect(store.bindings(for: .readScreenArea).map(\.enabled) == ([false]))
    }

    @Test func testMigrationLeavesScreenAreaEmptyWhenBothDefaultsConflict() throws {
        let data = Data(#"{"version":2,"actions":{"playPause":[{"shortcut":{"key":"two","modifiers":["control"]}}],"stop":[{"shortcut":{"key":"f16","modifiers":[]}}]}}"#.utf8)
        let decoded = try ShortcutConfigCodec.decodeBindings(from: data)
        #expect((decoded[.readScreenArea]) == ([]))
        #expect((decoded[.playPause]?.count) == 1)
        #expect((decoded[.stop]?.count) == 1)
    }

    @Test func testRecorderReenablesDisabledBindingForSameOrDifferentKey() throws {
        let configURL = makeTemporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"f18","modifiers":[]},"enabled":false,"source":"default"}]}}"#.utf8)
        for useSameKey in [true, false] {
            try data.write(to: configURL, options: .atomic)
            let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                      syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
            let existing = try #require(store.bindings(for: .readScreenArea).first)
            let shortcut = useSameKey ? existing.shortcut : ShortcutAction.readScreenArea.defaultBindings[1].shortcut
            store.updateBinding(id: existing.id, in: .readScreenArea, shortcut: shortcut)
            #expect(store.banner == nil)
            #expect((store.bindings(for: .readScreenArea).first?.shortcut) == shortcut)
            #expect((store.bindings(for: .readScreenArea).first?.enabled) == true)
            #expect((store.bindings(for: .readScreenArea).first?.source) == .custom)
            let saved = try ShortcutConfigCodec.decodeBindings(from: Data(contentsOf: configURL))
            #expect((saved[.readScreenArea]?.first?.enabled) == true)
        }
    }

    @Test func testDisabledBindingsSurviveLaunchAndReloadInPathWithSpaces() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReadPlease config \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appending(path: "shortcuts.json")
        let data = Data(#"{"version":2,"actions":{"playPause":[],"stop":[],"readScreenArea":[{"shortcut":{"key":"two","modifiers":["control"]},"enabled":false,"source":"default"},{"shortcut":{"key":"f16","modifiers":[]},"enabled":true,"source":"default"}]}}"#.utf8)
        try data.write(to: configURL)
        let store = ShortcutStore(configFileURL: configURL, registerBindingsOnChanges: false,
                                  syncRecorderStorageOnChanges: false, purgeKeyboardShortcutsOnInit: false)
        #expect(store.banner == nil)
        #expect(store.bindings(for: .readScreenArea).map(\.enabled) == ([false, true]))
        store.reloadFromDiskManually()
        #expect(store.bindings(for: .readScreenArea).map(\.enabled) == ([false, true]))
        #expect((try Data(contentsOf: configURL)) == data)
    }

    private func makeTemporaryConfigURL() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return root.appendingPathComponent("shortcuts.json")
    }

    private func loadJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
