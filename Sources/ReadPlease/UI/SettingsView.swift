import AVFoundation
import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var playbackManager: PlaybackManager
    @Bindable var shortcutStore: ShortcutStore
    @Bindable private var audioInterruptionSettings = AudioInterruptionSettings.shared
    let onboarding: OnboardingCoordinator

    @Environment(\.openWindow) private var openWindow
    @State private var showRestoreConfirm = false

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Form {
            Section("Reading") {
                LabeledContent {
                    VoicePopUpButton(selectedVoiceIdentifier: $playbackManager.currentVoiceId)
                        .fixedSize(horizontal: true, vertical: false)
                } label: {
                    Label("Voice", systemImage: "person.wave.2")
                }
                .settingsSpotlightAnchor(.voice)

                Picker(selection: $playbackManager.currentRate) {
                    ForEach(speedOptions, id: \.self) { rate in
                        Text(String(format: "%.2fx", rate)).tag(rate)
                    }
                } label: {
                    Label("Speed", systemImage: "speedometer")
                }
                .pickerStyle(.menu)

                LabeledContent {
                    Button("Play Sample") { playbackManager.previewVoice() }
                } label: {
                    Label("Preview voice", systemImage: "play.circle")
                }
            }

            Section("Shortcuts") {
                ForEach(shortcutStore.orderedActions, id: \.self) { action in
                    LabeledContent {
                        shortcutRecorder(for: action)
                    } label: {
                        Label(action.title, systemImage: icon(for: action))
                    }
                    .settingsSpotlightAnchor(.shortcuts)
                }

                // Surfaces shortcuts.json load/save problems (e.g. a typo or duplicate key after
                // editing the JSON by hand), which otherwise fail silently.
                if let banner = shortcutStore.banner, banner.tone == .error {
                    Label(banner.text, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Advanced") {
                Picker(selection: $audioInterruptionSettings.mode) {
                    ForEach(AudioInterruptionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("Audio interruption", systemImage: "speaker.slash")
                }
                .pickerStyle(.menu)
                .onChange(of: audioInterruptionSettings.mode) {
                    playbackManager.audioInterruptionModeDidChange()
                }

                LabeledContent {
                    Button("Open") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "scratchpad")
                    }
                } label: {
                    Label("Scratchpad", systemImage: "note.text")
                }

                LabeledContent {
                    HStack {
                        Button("Edit JSON") {
                            PronunciationStore.shared.openConfigFile()
                        }
                        Button("Reload") {
                            PronunciationStore.shared.reload()
                        }
                    }
                } label: {
                    Label("Pronunciations", systemImage: "text.bubble")
                }

                LabeledContent {
                    Button("Edit JSON") {
                        shortcutStore.openConfigFile()
                    }
                } label: {
                    Label("Advanced shortcuts", systemImage: "keyboard")
                }

                LabeledContent {
                    Button("Restore Defaults…", role: .destructive) {
                        showRestoreConfirm = true
                    }
                } label: {
                    Label("Restore default shortcuts", systemImage: "arrow.counterclockwise")
                }
            }

            Section("About") {
                LabeledContent {
                    Text(versionText)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Read Please", systemImage: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .settingsSpotlightOverlay(active: onboarding.spotlight)
        .task {
            shortcutStore.reloadFromDiskIfNeeded()
        }
        .alert("Restore default shortcuts?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) {
                shortcutStore.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces all custom shortcuts, including any added by editing shortcuts.json, with the defaults."
            )
        }
    }

    @ViewBuilder
    private func shortcutRecorder(for action: ShortcutAction) -> some View {
        if let primary = shortcutStore.bindings(for: action).first {
            KeyboardShortcuts.Recorder(for: primary.recorderName) { newShortcut in
                shortcutStore.updateBinding(id: primary.id, in: action, shortcut: newShortcut)
            }
        } else {
            KeyboardShortcuts.Recorder(
                for: KeyboardShortcuts.Name("ReadPlease.shortcut.\(action.rawValue).primaryDraft")
            ) { newShortcut in
                if let newShortcut {
                    shortcutStore.addBinding(newShortcut, to: action)
                }
            }
        }
    }

    private func icon(for action: ShortcutAction) -> String {
        switch action {
        case .playPause:
            "playpause"
        case .stop:
            "stop.fill"
        case .readScreenArea:
            "viewfinder"
        }
    }

    private var versionText: String {
        let shortVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Read Please v\(shortVersion) (\(build))"
    }
}

@MainActor
private struct VoicePopUpButton: NSViewRepresentable {
    @Binding var selectedVoiceIdentifier: String?

    // en-US and en-GB are pinned to the top; remaining English locales sort by localized name.
    private let preferredLocaleOrder: [String] = ["en-US", "en-GB"]

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedVoiceIdentifier: $selectedVoiceIdentifier)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        popUpButton.target = context.coordinator
        popUpButton.action = #selector(Coordinator.selectionChanged(_:))
        popUpButton.setContentHuggingPriority(.required, for: .horizontal)
        popUpButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
        return popUpButton
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        // Only rebuild the menu when the available voices actually change. Rebuilding on every
        // SwiftUI update — including the update triggered by the pop-up's own selection event —
        // resets the menu mid-event and drops the first click. When the voice set is unchanged we
        // just refresh the checkmarks/selection on the existing menu instead.
        // Classify once and reuse for both the cache comparison and the menu build —
        // classifyEnglishVoices() calls AVSpeechSynthesisVoice.speechVoices() and is not free.
        let classification = classifyEnglishVoices()
        let voiceIdentifiers = pickerVoiceIdentifiers(from: classification)
        let menu: NSMenu
        if let existingMenu = nsView.menu, context.coordinator.builtVoiceIdentifiers == voiceIdentifiers {
            menu = existingMenu
            refreshSelectionState(in: menu)
        } else {
            menu = buildMenu(classification: classification)
            nsView.menu = menu
            context.coordinator.builtVoiceIdentifiers = voiceIdentifiers
        }

        if let selectedVoiceIdentifier,
            let item = findMenuItem(in: menu, representedObject: selectedVoiceIdentifier)
        {
            nsView.select(item)
            return
        }

        if let systemDefaultItem = findMenuItem(in: menu, representedObject: SystemDefaultToken.shared) {
            nsView.select(systemDefaultItem)
        }
    }

    // Updates the .on/.off checkmark state across the menu without replacing it. Only the FIRST item
    // matching the selected identifier is checked so the checkmark stays on the item whose title the
    // pop-up displays (first-match-wins; harmless even though each voice now appears only once).
    private func refreshSelectionState(in menu: NSMenu) {
        var checkmarkPlaced = false
        refreshSelectionState(in: menu, checkmarkPlaced: &checkmarkPlaced)
    }

    private func refreshSelectionState(in menu: NSMenu, checkmarkPlaced: inout Bool) {
        for item in menu.items {
            if item.representedObject is SystemDefaultToken {
                item.state = selectedVoiceIdentifier == nil ? .on : .off
            } else if let identifier = item.representedObject as? String {
                if selectedVoiceIdentifier == identifier && !checkmarkPlaced {
                    item.state = .on
                    checkmarkPlaced = true
                } else {
                    item.state = .off
                }
            }
            if let submenu = item.submenu {
                refreshSelectionState(in: submenu, checkmarkPlaced: &checkmarkPlaced)
            }
        }
    }

    private func buildMenu(classification: VoiceClassification) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Each selectable voice appears once; track whether the selected identifier's single
        // checkmark has already been placed (first match wins) so we never check more than one.
        var checkmarkPlaced = false

        let systemDefaultItem = NSMenuItem(title: "System Default", action: nil, keyEquivalent: "")
        systemDefaultItem.representedObject = SystemDefaultToken.shared
        systemDefaultItem.state = selectedVoiceIdentifier == nil ? .on : .off
        menu.addItem(systemDefaultItem)

        // Locale groups for Vocalizer voices (compact + (Enhanced)/(Premium) variants inline).
        if !classification.localeGroups.isEmpty {
            menu.addItem(.separator())
        }

        for (index, group) in classification.localeGroups.enumerated() {
            let headerTitle = Locale.current.localizedString(forIdentifier: group.language)
                ?? group.language
            let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            headerItem.representedObject = HeaderToken.shared
            menu.addItem(headerItem)

            for voice in group.voices {
                addVoiceItem(voice, title: variantTitle(for: voice), to: menu, checkmarkPlaced: &checkmarkPlaced)
            }

            if index != classification.localeGroups.count - 1 {
                menu.addItem(.separator())
            }
        }

        // Classic section — inline (not a submenu, so selection works): Siri (ttsbundle) then MacinTalk voices.
        let classicVoices = classification.classicVoices
        if !classicVoices.isEmpty {
            menu.addItem(.separator())

            let classicHeader = NSMenuItem(title: "Classic", action: nil, keyEquivalent: "")
            classicHeader.isEnabled = false
            classicHeader.representedObject = HeaderToken.shared
            menu.addItem(classicHeader)

            for voice in classicVoices {
                addVoiceItem(voice, title: voice.name, to: menu, checkmarkPlaced: &checkmarkPlaced)
            }
        }

        return menu
    }

    private func addVoiceItem(
        _ voice: AVSpeechSynthesisVoice,
        title: String,
        to menu: NSMenu,
        checkmarkPlaced: inout Bool
    ) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = voice.identifier
        if selectedVoiceIdentifier == voice.identifier && !checkmarkPlaced {
            item.state = .on
            checkmarkPlaced = true
        } else {
            item.state = .off
        }
        menu.addItem(item)
    }

    // Plain-parentheses variant labels matching macOS's "Manage Voices" UI.
    private func variantTitle(for voice: AVSpeechSynthesisVoice) -> String {
        if voice.identifier.hasPrefix("com.apple.voice.premium.") {
            return "\(voice.name) (Premium)"
        }
        if voice.identifier.hasPrefix("com.apple.voice.enhanced.") {
            return "\(voice.name) (Enhanced)"
        }
        return voice.name
    }

    private func findMenuItem(in menu: NSMenu, representedObject target: AnyObject) -> NSMenuItem? {
        for item in menu.items {
            if let representedObject = item.representedObject as AnyObject?,
                representedObject === target
            {
                return item
            }

            if let submenu = item.submenu, let found = findMenuItem(in: submenu, representedObject: target) {
                return found
            }
        }
        return nil
    }

    private func findMenuItem(in menu: NSMenu, representedObject target: String) -> NSMenuItem? {
        for item in menu.items {
            if let representedObject = item.representedObject as? String, representedObject == target {
                return item
            }

            if let submenu = item.submenu, let found = findMenuItem(in: submenu, representedObject: target) {
                return found
            }
        }
        return nil
    }

    private var allSystemVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    // The set of voice identifiers that appear in the picker, used to detect when a menu
    // rebuild is actually required (see updateNSView).
    private func pickerVoiceIdentifiers(from classification: VoiceClassification) -> Set<String> {
        var ids = Set<String>()
        for group in classification.localeGroups {
            ids.formUnion(group.voices.map(\.identifier))
        }
        ids.formUnion(classification.classicVoices.map(\.identifier))
        return ids
    }

    // Quality rank for Vocalizer voices: default < enhanced < premium.
    private func vocalizerQualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        if voice.identifier.hasPrefix("com.apple.voice.premium.") { return 2 }
        if voice.identifier.hasPrefix("com.apple.voice.enhanced.") { return 1 }
        return 0
    }

    // Classifies every English voice into the picker's sections by identifier prefix.
    // Eloquence and novelty voices are dropped entirely.
    private func classifyEnglishVoices() -> VoiceClassification {
        let englishVoices = allSystemVoices.filter { voice in
            voice.language.hasPrefix("en")
                && !voice.identifier.hasPrefix("com.apple.eloquence.")
                && !voice.voiceTraits.contains(.isNoveltyVoice)
        }

        func nameAscending(_ lhs: AVSpeechSynthesisVoice, _ rhs: AVSpeechSynthesisVoice) -> Bool {
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        // Locale groups: all Vocalizer "com.apple.voice.*" voices (compact + enhanced + premium).
        let vocalizerVoices = englishVoices.filter { $0.identifier.hasPrefix("com.apple.voice.") }
        let grouped = Dictionary(grouping: vocalizerVoices, by: { $0.language })

        let sortedLanguages = grouped.keys.sorted { left, right in
            let leftIndex = preferredLocaleOrder.firstIndex(of: left)
            let rightIndex = preferredLocaleOrder.firstIndex(of: right)

            switch (leftIndex, rightIndex) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                let leftTitle = Locale.current.localizedString(forIdentifier: left) ?? left
                let rightTitle = Locale.current.localizedString(forIdentifier: right) ?? right
                return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
            }
        }

        let localeGroups: [LocaleVoiceGroup] = sortedLanguages.compactMap { language in
            guard let voices = grouped[language], !voices.isEmpty else { return nil }
            let sorted = voices.sorted { lhs, rhs in
                if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
                    return nameAscending(lhs, rhs)
                }
                return vocalizerQualityRank(lhs) < vocalizerQualityRank(rhs)
            }
            return LocaleVoiceGroup(language: language, voices: sorted)
        }

        // Classic submenu: Siri (ttsbundle) voices first, then non-novelty MacinTalk voices.
        let siriVoices = englishVoices
            .filter { $0.identifier.hasPrefix("com.apple.ttsbundle.siri") }
            .sorted(by: nameAscending)
        let macinTalkVoices = englishVoices
            .filter { $0.identifier.hasPrefix("com.apple.speech.synthesis.voice.") }
            .sorted(by: nameAscending)
        let classicVoices = siriVoices + macinTalkVoices

        return VoiceClassification(
            localeGroups: localeGroups,
            classicVoices: classicVoices
        )
    }

    private struct VoiceClassification {
        let localeGroups: [LocaleVoiceGroup]
        let classicVoices: [AVSpeechSynthesisVoice]
    }

    private struct LocaleVoiceGroup {
        let language: String
        let voices: [AVSpeechSynthesisVoice]
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var selectedVoiceIdentifier: String?

        // The voice identifiers used to build the current menu, so updateNSView can detect when
        // a rebuild is actually needed instead of replacing the menu on every update.
        var builtVoiceIdentifiers: Set<String>?

        init(selectedVoiceIdentifier: Binding<String?>) {
            self._selectedVoiceIdentifier = selectedVoiceIdentifier
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let representedObject = sender.selectedItem?.representedObject else { return }

            if representedObject is SystemDefaultToken {
                selectedVoiceIdentifier = nil
            } else if let voiceIdentifier = representedObject as? String {
                selectedVoiceIdentifier = voiceIdentifier
            }
        }
    }

    @MainActor
    private final class SystemDefaultToken: NSObject {
        static let shared = SystemDefaultToken()
    }

    @MainActor
    private final class HeaderToken: NSObject {
        static let shared = HeaderToken()
    }
}
