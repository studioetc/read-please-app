import AppKit
import Foundation

struct PronunciationRule: Codable, Sendable {
    let term: String
    let value: String
}

struct IPARule: Codable, Sendable {
    let term: String
    let ipa: String
}

struct PronunciationConfigFile: Codable, Sendable {
    let version: Int
    let rules: [PronunciationRule]
    let ipaRules: [IPARule]

    enum CodingKeys: String, CodingKey {
        case version
        case rules
        case ipaRules = "ipa_rules"
    }
}

struct PronunciationRuleSet: Sendable {
    let rules: [PronunciationRule]
    let ipaRules: [IPARule]
}

final class PronunciationStore: @unchecked Sendable {
    static let shared = PronunciationStore()

    private enum Constants {
        static let configVersion = 1
        static let configFileName = "pronunciations.json"
    }

    let configFileURL: URL

    private let lock = NSLock()
    private var currentRuleSet: PronunciationRuleSet

    var ruleSet: PronunciationRuleSet {
        lock.lock()
        defer { lock.unlock() }
        return currentRuleSet
    }

    init(configFileURL: URL = PronunciationStore.makeConfigFileURL()) {
        self.configFileURL = configFileURL
        self.currentRuleSet = Self.loadRuleSet(at: configFileURL)
    }

    /// Re-reads and re-validates the config file. On failure, keeps the last good rules.
    func reload() {
        guard let reloaded = Self.loadRuleSet(at: configFileURL, bootstrapIfMissing: false) else {
            return
        }

        lock.lock()
        currentRuleSet = reloaded
        lock.unlock()
    }

    /// Ensures the config file exists, then opens it in the default editor.
    func openConfigFile() {
        try? Self.ensureConfigFileExists(at: configFileURL)
        // If the default JSON editor can't be launched (e.g. it's running from a deleted
        // update folder), show the file in Finder instead of failing silently.
        if !NSWorkspace.shared.open(configFileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([configFileURL])
        }
    }

    private static func loadRuleSet(at configFileURL: URL) -> PronunciationRuleSet {
        loadRuleSet(at: configFileURL, bootstrapIfMissing: true)
            ?? PronunciationRuleSet(rules: [], ipaRules: [])
    }

    /// Returns a validated rule set, or `nil` if the file couldn't be read/validated.
    /// When `bootstrapIfMissing` is true, a default file is written if none exists.
    private static func loadRuleSet(
        at configFileURL: URL,
        bootstrapIfMissing: Bool
    ) -> PronunciationRuleSet? {
        do {
            if bootstrapIfMissing {
                try ensureConfigFileExists(at: configFileURL)
            }
            return try loadFromDisk(at: configFileURL)
        } catch {
            // Fail silently from the user's perspective.
            return nil
        }
    }

    private static func ensureConfigFileExists(at configFileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: configFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard !FileManager.default.fileExists(atPath: configFileURL.path(percentEncoded: false)) else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(defaultConfigFile).write(to: configFileURL, options: .atomic)
    }

    private static func loadFromDisk(at configFileURL: URL) throws -> PronunciationRuleSet {
        let data = try Data(contentsOf: configFileURL)
        let decoded = try JSONDecoder().decode(PronunciationConfigFile.self, from: data)

        guard decoded.version == Constants.configVersion else {
            throw PronunciationStoreError.invalidConfigVersion
        }

        return PronunciationRuleSet(
            rules: decoded.rules.filter { !$0.term.isEmpty && !$0.value.isEmpty },
            ipaRules: decoded.ipaRules.filter { !$0.term.isEmpty && !$0.ipa.isEmpty }
        )
    }

    private static var defaultConfigFile: PronunciationConfigFile {
        PronunciationConfigFile(
            version: Constants.configVersion,
            rules: [
                PronunciationRule(term: "github", value: "Git Hub"),
                PronunciationRule(term: "api", value: "API"),
                PronunciationRule(term: "url", value: "URL"),
                PronunciationRule(term: "TOS", value: "T O S"),
                PronunciationRule(term: "tos", value: "T O S"),
            ],
            ipaRules: []
        )
    }

    private static func makeConfigFileURL() -> URL {
        AppSupportPaths.configFileURL(fileName: Constants.configFileName)
    }
}

private enum PronunciationStoreError: Error {
    case invalidConfigVersion
}
