import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import Observation

@Observable
@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()

    private enum Constants {
        static let configFileName = "shortcuts.json"
    }

    private(set) var bindingsByAction: [ShortcutAction: [ShortcutBinding]]
    private(set) var banner: ShortcutStoreBanner?
    private(set) var configFileURL: URL

    private let registerBindingsOnChanges: Bool
    private let syncRecorderStorageOnChanges: Bool
    private let purgeKeyboardShortcutsOnInit: Bool

    private var syncedRecorderNames: Set<String> = []
    private var lastKnownFileModificationDate: Date?

    init(
        configFileURL: URL = ShortcutStore.makeConfigFileURL(),
        registerBindingsOnChanges: Bool = true,
        syncRecorderStorageOnChanges: Bool = true,
        purgeKeyboardShortcutsOnInit: Bool = true
    ) {
        self.bindingsByAction = Self.defaultBindingsByAction()
        self.configFileURL = configFileURL
        self.registerBindingsOnChanges = registerBindingsOnChanges
        self.syncRecorderStorageOnChanges = syncRecorderStorageOnChanges
        self.purgeKeyboardShortcutsOnInit = purgeKeyboardShortcutsOnInit

        if purgeKeyboardShortcutsOnInit {
            Self.purgeKeyboardShortcutsUserDefaults()
        }

        do {
            try ensureConfigFileExists()
            try loadFromDisk(force: true, announceSuccess: false)
        } catch {
            banner = ShortcutStoreBanner(
                tone: .error,
                text: error.localizedDescription
            )
        }

        syncRecorderStorage()
        refreshRuntimeBindings()
    }

    var orderedActions: [ShortcutAction] {
        ShortcutAction.allCases
    }

    func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        bindingsByAction[action] ?? []
    }

    func addBinding(_ shortcut: KeyboardShortcuts.Shortcut, to action: ShortcutAction) {
        var candidate = bindingsByAction
        candidate[action, default: []].append(
            ShortcutBinding(
                id: UUID().uuidString,
                shortcut: shortcut,
                enabled: true,
                source: .custom
            )
        )
        applyCandidate(candidate)
    }

    func updateBinding(
        id: String,
        in action: ShortcutAction,
        shortcut: KeyboardShortcuts.Shortcut?
    ) {
        guard let existing = binding(id: id, in: action) else { return }

        guard let shortcut else {
            removeBinding(id: id, in: action)
            return
        }

        guard existing.shortcut != shortcut || !existing.enabled else {
            syncRecorderStorage()
            return
        }

        var candidate = bindingsByAction
        candidate[action] = bindings(for: action).map { binding in
            guard binding.id == id else { return binding }
            var updated = binding
            updated.shortcut = shortcut
            updated.enabled = true
            if updated.source == .defaultValue {
                updated.source = .custom
            }
            return updated
        }
        applyCandidate(candidate)
    }

    func removeBinding(id: String, in action: ShortcutAction) {
        guard let existing = binding(id: id, in: action) else { return }

        var candidate = bindingsByAction
        candidate[action] = bindings(for: action).filter { $0.id != id }
        applyCandidate(candidate, staleRecorderNames: [existing.recorderNameRawValue])
    }

    func resetAll() {
        let staleNames = Set(
            bindingsByAction.values
                .flatMap { $0 }
                .map(\.recorderNameRawValue)
        )
        applyCandidate(Self.defaultBindingsByAction(), staleRecorderNames: staleNames)
    }

    func openConfigFile() {
        persistCurrentState()
        guard NSWorkspace.shared.open(configFileURL) else {
            banner = ShortcutStoreBanner(
                tone: .error,
                text: "Couldn't open shortcuts.json in the default editor."
            )
            return
        }
    }

    func reloadFromDiskIfNeeded() {
        do {
            let currentModificationDate = try fileModificationDate(for: configFileURL)
            guard currentModificationDate != lastKnownFileModificationDate else { return }
            try loadFromDisk(force: true, announceSuccess: false)
        } catch {
            banner = ShortcutStoreBanner(
                tone: .error,
                text: error.localizedDescription
            )
        }
    }

    func reloadFromDiskManually() {
        do {
            try loadFromDisk(force: true, announceSuccess: true)
        } catch {
            banner = ShortcutStoreBanner(
                tone: .error,
                text: error.localizedDescription
            )
        }
    }

    private func loadFromDisk(force: Bool, announceSuccess: Bool) throws {
        if !FileManager.default.fileExists(atPath: configFileURL.path(percentEncoded: false)) {
            try ensureConfigFileExists()
        }

        let data = try Data(contentsOf: configFileURL)
        let decoded = try ShortcutConfigCodec.decodeFile(from: data)
        let candidate = decoded.bindingsByAction

        try validate(candidate)
        bindingsByAction = candidate
        syncRecorderStorage()
        refreshRuntimeBindings()

        if decoded.needsMigration {
            persistCurrentState()
        } else {
            lastKnownFileModificationDate = try fileModificationDate(for: configFileURL)
        }

        if announceSuccess {
            banner = ShortcutStoreBanner(
                tone: .success,
                text: "Reloaded shortcuts from shortcuts.json."
            )
        } else if force {
            banner = nil
        }
    }

    private func applyCandidate(
        _ candidate: [ShortcutAction: [ShortcutBinding]],
        staleRecorderNames: Set<String> = []
    ) {
        do {
            try validate(candidate)
            bindingsByAction = candidate
            persistCurrentState(additionallyClearing: staleRecorderNames)
            syncRecorderStorage()
            refreshRuntimeBindings()
            banner = nil
        } catch {
            syncRecorderStorage()
            banner = ShortcutStoreBanner(
                tone: .error,
                text: error.localizedDescription
            )
        }
    }

    private func validate(_ candidate: [ShortcutAction: [ShortcutBinding]]) throws {
        var seenIDs = Set<String>()
        var seenShortcuts = Set<KeyboardShortcuts.Shortcut>()

        for action in ShortcutAction.allCases {
            for binding in candidate[action] ?? [] {
                guard seenIDs.insert(binding.id).inserted else {
                    throw ShortcutStoreError.duplicateID(binding.id)
                }

                guard binding.enabled else { continue }

                guard seenShortcuts.insert(binding.shortcut).inserted else {
                    throw ShortcutStoreError.duplicateShortcut(binding.shortcut.description)
                }
            }
        }
    }

    private func ensureConfigFileExists() throws {
        try FileManager.default.createDirectory(
            at: configDirectoryURL(),
            withIntermediateDirectories: true
        )

        guard !FileManager.default.fileExists(atPath: configFileURL.path(percentEncoded: false)) else { return }
        persistCurrentState()
    }

    private func persistCurrentState(additionallyClearing staleRecorderNames: Set<String> = []) {
        do {
            let data = try ShortcutConfigCodec.encodeFile(bindingsByAction)
            try FileManager.default.createDirectory(
                at: configDirectoryURL(),
                withIntermediateDirectories: true
            )
            try data.write(to: configFileURL, options: .atomic)
            lastKnownFileModificationDate = try fileModificationDate(for: configFileURL)

            if !staleRecorderNames.isEmpty {
                syncRecorderStorage(clearing: staleRecorderNames)
            }
        } catch {
            banner = ShortcutStoreBanner(
                tone: .error,
                text: ShortcutStoreError.saveFailed(error.localizedDescription).localizedDescription
            )
        }
    }

    private func syncRecorderStorage(clearing explicitlyClearedNames: Set<String> = []) {
        guard syncRecorderStorageOnChanges else { return }

        let currentBindings = bindingsByAction.values.flatMap { $0 }
        let activeNames = Set(currentBindings.map(\.recorderNameRawValue))

        for binding in currentBindings {
            KeyboardShortcuts.setShortcut(binding.shortcut, for: binding.recorderName)
        }

        for staleName in syncedRecorderNames
            .subtracting(activeNames)
            .union(explicitlyClearedNames)
        {
            KeyboardShortcuts.setShortcut(nil, for: .init(staleName))
        }

        syncedRecorderNames = activeNames
    }

    private func refreshRuntimeBindings() {
        guard registerBindingsOnChanges else { return }
        ShortcutManager.shared.registerBindings(bindingsByAction)
    }

    private func binding(id: String, in action: ShortcutAction) -> ShortcutBinding? {
        bindings(for: action).first { $0.id == id }
    }

    private func configDirectoryURL() -> URL {
        configFileURL.deletingLastPathComponent()
    }

    private func fileModificationDate(for url: URL) throws -> Date? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
    }

    private static func defaultBindingsByAction() -> [ShortcutAction: [ShortcutBinding]] {
        ShortcutAction.allCases.reduce(into: [ShortcutAction: [ShortcutBinding]]()) { result, action in
            result[action] = action.defaultBindings
        }
    }

    private static func makeConfigFileURL() -> URL {
        AppSupportPaths.configFileURL(fileName: Constants.configFileName)
    }

    private static func purgeKeyboardShortcutsUserDefaults() {
        let prefixes = [
            "KeyboardShortcuts_ReadPlease.shortcut.",
            "KeyboardShortcuts_ReadPlease.shortcutDraft.",
        ]

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            guard prefixes.contains(where: key.hasPrefix) else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}

struct ShortcutConfigCodec {
    struct DecodedFile: Sendable {
        let version: Int
        let needsMigration: Bool
        let bindingsByAction: [ShortcutAction: [ShortcutBinding]]
    }

    private struct ConfigVersionEnvelope: Decodable {
        let version: Int
    }

    private struct ShortcutConfigFileV2: Codable {
        let version: Int
        let actions: [String: [PersistedBindingV2]]
    }

    private struct PersistedBindingV2: Codable {
        let description: String?
        let enabled: Bool?
        let shortcut: PersistedShortcutV2
        let source: ShortcutBindingSource?
    }

    private struct PersistedShortcutV2: Codable {
        let key: String
        let modifiers: [String]
    }

    private struct ShortcutConfigFileV1: Decodable {
        let version: Int
        let actions: [String: [PersistedBindingV1]]
    }

    private struct PersistedBindingV1: Decodable {
        let description: String?
        let enabled: Bool?
        let shortcut: PersistedShortcutV1
        let source: ShortcutBindingSource?
    }

    private struct PersistedShortcutV1: Decodable {
        let carbonKeyCode: Int
        let carbonModifiers: Int?
    }

    static func decodeFile(from data: Data) throws -> DecodedFile {
        let decoder = JSONDecoder()

        do {
            let version = try decoder.decode(ConfigVersionEnvelope.self, from: data).version

            switch version {
            case 1:
                let file = try decoder.decode(ShortcutConfigFileV1.self, from: data)
                let bindings = try decodeBindings(file.actions) { binding in
                    try ShortcutBinding(
                        id: UUID().uuidString,
                        description: normalizedDescription(binding.description),
                        shortcut: shortcut(fromLegacy: binding.shortcut),
                        enabled: binding.enabled ?? true,
                        source: binding.source ?? .custom
                    )
                }
                return DecodedFile(version: 1, needsMigration: true, bindingsByAction: bindings)
            case 2:
                let file = try decoder.decode(ShortcutConfigFileV2.self, from: data)
                let bindings = try decodeBindings(file.actions) { binding in
                    try ShortcutBinding(
                        id: UUID().uuidString,
                        description: normalizedDescription(binding.description),
                        shortcut: shortcut(fromReadable: binding.shortcut),
                        enabled: binding.enabled ?? true,
                        source: binding.source ?? .custom
                    )
                }
                return DecodedFile(
                    version: 2,
                    needsMigration: file.actions[ShortcutAction.readScreenArea.rawValue] == nil,
                    bindingsByAction: bindings
                )
            default:
                throw ShortcutStoreError.invalidConfig(
                    "shortcuts.json has version \(version), but this build expects version 1 or 2."
                )
            }
        } catch let error as ShortcutStoreError {
            throw error
        } catch {
            throw ShortcutStoreError.invalidConfig(
                "Couldn't read shortcuts.json: \(error.localizedDescription)"
            )
        }
    }

    static func decodeBindings(from data: Data) throws -> [ShortcutAction: [ShortcutBinding]] {
        try decodeFile(from: data).bindingsByAction
    }

    static func encodeFile(_ bindingsByAction: [ShortcutAction: [ShortcutBinding]]) throws -> Data {
        let actions = try ShortcutAction.allCases.reduce(into: [String: [PersistedBindingV2]]()) { result, action in
            result[action.rawValue] = try (bindingsByAction[action] ?? []).map { binding in
                PersistedBindingV2(
                    description: normalizedDescription(binding.description),
                    enabled: binding.enabled,
                    shortcut: try readableShortcut(from: binding.shortcut),
                    source: binding.source
                )
            }
        }

        let file = ShortcutConfigFileV2(version: 2, actions: actions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    private static func decodeBindings<T>(
        _ actions: [String: [T]],
        transform: (T) throws -> ShortcutBinding
    ) throws -> [ShortcutAction: [ShortcutBinding]] {
        var result = try ShortcutAction.allCases.reduce(into: [ShortcutAction: [ShortcutBinding]]()) { result, action in
            result[action] = try (actions[action.rawValue] ?? []).map(transform)
        }
        if actions[ShortcutAction.readScreenArea.rawValue] == nil {
            let used = Set(result.values.flatMap { $0 }.filter(\.enabled).map(\.shortcut))
            // Existing shortcuts win; the first remaining default must be usable in Settings.
            result[.readScreenArea] = ShortcutAction.readScreenArea.defaultBindings.filter {
                !used.contains($0.shortcut)
            }
        }
        return result
    }

    private static func normalizedDescription(_ description: String?) -> String? {
        guard let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func shortcut(fromReadable readableShortcut: PersistedShortcutV2) throws -> KeyboardShortcuts.Shortcut {
        let keyCode = try ShortcutKey.carbonKeyCode(for: readableShortcut.key)
        let modifiers = try ShortcutModifier.carbonModifiers(for: readableShortcut.modifiers)
        return KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers)
    }

    private static func shortcut(fromLegacy legacyShortcut: PersistedShortcutV1) throws -> KeyboardShortcuts.Shortcut {
        let shortcut = KeyboardShortcuts.Shortcut(
            carbonKeyCode: legacyShortcut.carbonKeyCode,
            carbonModifiers: legacyShortcut.carbonModifiers ?? 0
        )

        guard ShortcutKey.name(for: shortcut.carbonKeyCode) != nil else {
            throw ShortcutStoreError.invalidConfig(
                "Legacy shortcut uses unsupported key code \(legacyShortcut.carbonKeyCode)."
            )
        }

        return shortcut
    }

    private static func readableShortcut(from shortcut: KeyboardShortcuts.Shortcut) throws -> PersistedShortcutV2 {
        guard let keyName = ShortcutKey.name(for: shortcut.carbonKeyCode) else {
            throw ShortcutStoreError.invalidConfig(
                "Shortcut with key code \(shortcut.carbonKeyCode) cannot be written because its key code is unsupported."
            )
        }

        return PersistedShortcutV2(
            key: keyName,
            modifiers: ShortcutModifier.names(from: shortcut.carbonModifiers)
        )
    }
}

enum ShortcutModifier: String, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command
    case function

    private static let functionKeyFlag = 1 << 17

    var carbonFlag: Int {
        switch self {
        case .control:
            Int(controlKey)
        case .option:
            Int(optionKey)
        case .shift:
            Int(shiftKey)
        case .command:
            Int(cmdKey)
        case .function:
            Self.functionKeyFlag
        }
    }

    static func normalizeCarbonModifiers(_ carbonModifiers: Int) -> Int {
        allCases.reduce(into: 0) { result, modifier in
            if carbonModifiers & modifier.carbonFlag == modifier.carbonFlag {
                result |= modifier.carbonFlag
            }
        }
    }

    static func carbonModifiers(for modifierNames: [String]) throws -> Int {
        var modifiers = 0

        for modifierName in modifierNames {
            let normalized = modifierName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let modifier = ShortcutModifier(rawValue: normalized) else {
                throw ShortcutStoreError.invalidConfig(
                    "Unknown shortcut modifier '\(modifierName)'. Supported modifiers are: \(allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            modifiers |= modifier.carbonFlag
        }

        return normalizeCarbonModifiers(modifiers)
    }

    static func names(from carbonModifiers: Int) -> [String] {
        let normalized = normalizeCarbonModifiers(carbonModifiers)
        return allCases.compactMap { modifier in
            normalized & modifier.carbonFlag == modifier.carbonFlag ? modifier.rawValue : nil
        }
    }
}

enum ShortcutKey {
    private static let entries: [(String, Int)] = [
        ("a", Int(kVK_ANSI_A)),
        ("b", Int(kVK_ANSI_B)),
        ("c", Int(kVK_ANSI_C)),
        ("d", Int(kVK_ANSI_D)),
        ("e", Int(kVK_ANSI_E)),
        ("f", Int(kVK_ANSI_F)),
        ("g", Int(kVK_ANSI_G)),
        ("h", Int(kVK_ANSI_H)),
        ("i", Int(kVK_ANSI_I)),
        ("j", Int(kVK_ANSI_J)),
        ("k", Int(kVK_ANSI_K)),
        ("l", Int(kVK_ANSI_L)),
        ("m", Int(kVK_ANSI_M)),
        ("n", Int(kVK_ANSI_N)),
        ("o", Int(kVK_ANSI_O)),
        ("p", Int(kVK_ANSI_P)),
        ("q", Int(kVK_ANSI_Q)),
        ("r", Int(kVK_ANSI_R)),
        ("s", Int(kVK_ANSI_S)),
        ("t", Int(kVK_ANSI_T)),
        ("u", Int(kVK_ANSI_U)),
        ("v", Int(kVK_ANSI_V)),
        ("w", Int(kVK_ANSI_W)),
        ("x", Int(kVK_ANSI_X)),
        ("y", Int(kVK_ANSI_Y)),
        ("z", Int(kVK_ANSI_Z)),
        ("zero", Int(kVK_ANSI_0)),
        ("one", Int(kVK_ANSI_1)),
        ("two", Int(kVK_ANSI_2)),
        ("three", Int(kVK_ANSI_3)),
        ("four", Int(kVK_ANSI_4)),
        ("five", Int(kVK_ANSI_5)),
        ("six", Int(kVK_ANSI_6)),
        ("seven", Int(kVK_ANSI_7)),
        ("eight", Int(kVK_ANSI_8)),
        ("nine", Int(kVK_ANSI_9)),
        ("return", Int(kVK_Return)),
        ("backslash", Int(kVK_ANSI_Backslash)),
        ("backtick", Int(kVK_ANSI_Grave)),
        ("comma", Int(kVK_ANSI_Comma)),
        ("equal", Int(kVK_ANSI_Equal)),
        ("minus", Int(kVK_ANSI_Minus)),
        ("period", Int(kVK_ANSI_Period)),
        ("quote", Int(kVK_ANSI_Quote)),
        ("semicolon", Int(kVK_ANSI_Semicolon)),
        ("slash", Int(kVK_ANSI_Slash)),
        ("space", Int(kVK_Space)),
        ("tab", Int(kVK_Tab)),
        ("leftBracket", Int(kVK_ANSI_LeftBracket)),
        ("rightBracket", Int(kVK_ANSI_RightBracket)),
        ("pageUp", Int(kVK_PageUp)),
        ("pageDown", Int(kVK_PageDown)),
        ("home", Int(kVK_Home)),
        ("end", Int(kVK_End)),
        ("upArrow", Int(kVK_UpArrow)),
        ("rightArrow", Int(kVK_RightArrow)),
        ("downArrow", Int(kVK_DownArrow)),
        ("leftArrow", Int(kVK_LeftArrow)),
        ("escape", Int(kVK_Escape)),
        ("delete", Int(kVK_Delete)),
        ("deleteForward", Int(kVK_ForwardDelete)),
        ("help", Int(kVK_Help)),
        ("mute", Int(kVK_Mute)),
        ("volumeUp", Int(kVK_VolumeUp)),
        ("volumeDown", Int(kVK_VolumeDown)),
        ("f1", Int(kVK_F1)),
        ("f2", Int(kVK_F2)),
        ("f3", Int(kVK_F3)),
        ("f4", Int(kVK_F4)),
        ("f5", Int(kVK_F5)),
        ("f6", Int(kVK_F6)),
        ("f7", Int(kVK_F7)),
        ("f8", Int(kVK_F8)),
        ("f9", Int(kVK_F9)),
        ("f10", Int(kVK_F10)),
        ("f11", Int(kVK_F11)),
        ("f12", Int(kVK_F12)),
        ("f13", Int(kVK_F13)),
        ("f14", Int(kVK_F14)),
        ("f15", Int(kVK_F15)),
        ("f16", Int(kVK_F16)),
        ("f17", Int(kVK_F17)),
        ("f18", Int(kVK_F18)),
        ("f19", Int(kVK_F19)),
        ("f20", Int(kVK_F20)),
        ("keypad0", Int(kVK_ANSI_Keypad0)),
        ("keypad1", Int(kVK_ANSI_Keypad1)),
        ("keypad2", Int(kVK_ANSI_Keypad2)),
        ("keypad3", Int(kVK_ANSI_Keypad3)),
        ("keypad4", Int(kVK_ANSI_Keypad4)),
        ("keypad5", Int(kVK_ANSI_Keypad5)),
        ("keypad6", Int(kVK_ANSI_Keypad6)),
        ("keypad7", Int(kVK_ANSI_Keypad7)),
        ("keypad8", Int(kVK_ANSI_Keypad8)),
        ("keypad9", Int(kVK_ANSI_Keypad9)),
        ("keypadClear", Int(kVK_ANSI_KeypadClear)),
        ("keypadDecimal", Int(kVK_ANSI_KeypadDecimal)),
        ("keypadDivide", Int(kVK_ANSI_KeypadDivide)),
        ("keypadEnter", Int(kVK_ANSI_KeypadEnter)),
        ("keypadEquals", Int(kVK_ANSI_KeypadEquals)),
        ("keypadMinus", Int(kVK_ANSI_KeypadMinus)),
        ("keypadMultiply", Int(kVK_ANSI_KeypadMultiply)),
        ("keypadPlus", Int(kVK_ANSI_KeypadPlus)),
    ]

    private static let keyCodesByName = Dictionary(uniqueKeysWithValues: entries)
    private static let namesByKeyCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.1, $0.0) })

    static func carbonKeyCode(for keyName: String) throws -> Int {
        let normalized = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyCode = keyCodesByName[normalized] else {
            throw ShortcutStoreError.invalidConfig(
                "Unknown shortcut key '\(keyName)'. Use a named macOS key such as f14, backslash, delete, one, or upArrow."
            )
        }

        return keyCode
    }

    static func name(for carbonKeyCode: Int) -> String? {
        namesByKeyCode[carbonKeyCode]
    }
}
