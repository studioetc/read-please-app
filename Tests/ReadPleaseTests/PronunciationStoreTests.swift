import Foundation
import Testing
@testable import ReadPlease

@Suite final class PronunciationStoreTests {
    /// Regression: a path containing a space (like "Application Support") was percent-encoded
    /// before the existence check, so the user's file was overwritten with defaults on launch.
    @Test func testExistingConfigInPathWithSpaceIsNotOverwritten() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pronunciation Tests \(UUID().uuidString)")
        let configURL = folderURL.appendingPathComponent("pronunciations.json")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let customJSON = #"{"version":1,"rules":[{"term":"CLIProxyAPI","value":"CLI Proxy API"}],"ipa_rules":[]}"#
        try Data(customJSON.utf8).write(to: configURL)

        let store = PronunciationStore(configFileURL: configURL)

        #expect(store.ruleSet.rules.map(\.term) == ["CLIProxyAPI"])
        #expect((try String(contentsOf: configURL, encoding: .utf8)) == customJSON)
    }
}
