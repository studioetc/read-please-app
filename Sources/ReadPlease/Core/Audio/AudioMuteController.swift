import AppKit
import AudioToolbox
import CoreAudio
import Foundation

@MainActor
protocol AudioMuting: AnyObject {
    @discardableResult
    func start(mode: AudioInterruptionMode) -> Bool
    func stop()
}

@MainActor
final class AudioMuteController: AudioMuting {
    static let shared = AudioMuteController()

    private let chromeBundleID = "com.google.Chrome"
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var activeMode: AudioInterruptionMode?

    private init() {}

    @discardableResult
    func start(mode: AudioInterruptionMode) -> Bool {
        if mode == .off {
            stop()
            return false
        }
        guard !isRunning || activeMode != mode else { return true }

        if hasAllocatedResources {
            stop()
            guard !hasAllocatedResources else {
                print("AudioMuteController: Previous audio mute resources could not be released")
                return false
            }
        }

        do {
            let tapDescription: CATapDescription
            let scopeDescription: String

            switch mode {
            case .off:
                preconditionFailure("The off mode is handled before tap creation")
            case .muteChromeWhileSpeaking:
                let chromeProcesses = try findChromeAudioProcesses()
                guard !chromeProcesses.isEmpty else {
                    print("AudioMuteController: No Chrome audio processes found")
                    return false
                }
                tapDescription = CATapDescription(stereoMixdownOfProcesses: chromeProcesses)
                scopeDescription = "Chrome"
            case .muteAllOtherAudioWhileSpeaking:
                let ownProcesses = try findOwnAudioProcesses()
                guard !ownProcesses.isEmpty else {
                    print(
                        "AudioMuteController: ReadPlease audio process is not available; "
                            + "global mute was not started"
                    )
                    return false
                }
                tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcesses)
                scopeDescription = "all audio except ReadPlease"
            }

            try prepareTap(description: tapDescription, scopeName: scopeDescription)
            try startTap()
            isRunning = true
            activeMode = mode
            print("AudioMuteController: Muting \(scopeDescription)")
            return true
        } catch {
            print("AudioMuteController: Failed to start audio mute: \(error)")
            stop()
            return false
        }
    }

    func stop() {
        let wasRunning = isRunning

        if aggregateDeviceID != kAudioObjectUnknown {
            if let ioProcID {
                let stopError = AudioDeviceStop(aggregateDeviceID, ioProcID)
                if stopError != noErr {
                    print("AudioMuteController: AudioDeviceStop failed: \(stopError)")
                }

                let destroyIOProcError = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                if destroyIOProcError != noErr {
                    print("AudioMuteController: AudioDeviceDestroyIOProcID failed: \(destroyIOProcError)")
                } else {
                    self.ioProcID = nil
                }
            }

            if ioProcID == nil {
                let destroyAggregateError = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                if destroyAggregateError != noErr {
                    print("AudioMuteController: AudioHardwareDestroyAggregateDevice failed: \(destroyAggregateError)")
                } else {
                    aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
                }
            }
        }

        if tapID != kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown {
            let destroyTapError = AudioHardwareDestroyProcessTap(tapID)
            if destroyTapError != noErr {
                print("AudioMuteController: AudioHardwareDestroyProcessTap failed: \(destroyTapError)")
            } else {
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }

        if wasRunning, !hasAllocatedResources {
            print("AudioMuteController: Audio mute stopped")
        }
        isRunning = false
        activeMode = nil
    }

    private var hasAllocatedResources: Bool {
        ioProcID != nil
            || aggregateDeviceID != kAudioObjectUnknown
            || tapID != kAudioObjectUnknown
    }

    private func findChromeAudioProcesses() throws -> [AudioObjectID] {
        let runningChromePIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == chromeBundleID }
                .map(\.processIdentifier)
        )

        return try AudioObjectID.readProcessList().filter { processID in
            let bundleID = (try? processID.readProcessBundleID()) as String?
            if let bundleID,
                bundleID == chromeBundleID || bundleID.hasPrefix("\(chromeBundleID).")
            {
                return true
            }

            if let pid = try? processID.readProcessPID(), runningChromePIDs.contains(pid) {
                return true
            }

            return false
        }
    }

    private func findOwnAudioProcesses() throws -> [AudioObjectID] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier

        return try AudioObjectID.readProcessList().filter { processID in
            if let pid = try? processID.readProcessPID(), pid == ownPID {
                return true
            }

            guard let ownBundleID,
                let processBundleID = (try? processID.readProcessBundleID()) as String?
            else {
                return false
            }
            return processBundleID == ownBundleID
        }
    }

    private func prepareTap(description tapDescription: CATapDescription, scopeName: String) throws {
        tapDescription.uuid = UUID()
        tapDescription.name = "ReadPlease \(scopeName) Mute"
        tapDescription.muteBehavior = .muted
        tapDescription.isPrivate = true
        if #available(macOS 26.0, *) {
            tapDescription.isProcessRestoreEnabled = true
        }

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try checkOSStatus(
            AudioHardwareCreateProcessTap(tapDescription, &newTapID),
            "AudioHardwareCreateProcessTap"
        )
        tapID = newTapID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ReadPlease Audio Mute",
            kAudioAggregateDeviceUIDKey: "com.onestepp.ReadPlease.AudioMute.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try checkOSStatus(
            AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &newAggregateDeviceID
            ),
            "AudioHardwareCreateAggregateDevice"
        )
        aggregateDeviceID = newAggregateDeviceID
    }

    private func startTap() throws {
        let callback: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
            // Keep the tap actively consuming audio while .muted suppresses hardware playback.
            _ = inInputData.pointee.mNumberBuffers
        }

        var newIOProcID: AudioDeviceIOProcID?
        try checkOSStatus(
            AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, aggregateDeviceID, nil, callback),
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        ioProcID = newIOProcID

        if let newIOProcID {
            try checkOSStatus(AudioDeviceStart(aggregateDeviceID, newIOProcID), "AudioDeviceStart")
        }
    }
}

private struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed with OSStatus \(status)"
    }
}

private func checkOSStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CoreAudioError(operation: operation, status: status)
    }
}

private extension AudioObjectID {
    static func readProcessList() throws -> [AudioObjectID] {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let dataSize = try readPropertyDataSize(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: address
        )
        let processCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: processCount
        )
        try processIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            try readPropertyData(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: address,
                data: baseAddress,
                dataSize: dataSize
            )
        }
        return processIDs
    }

    func readProcessPID() throws -> pid_t {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var pid = pid_t()
        try Self.readPropertyData(
            objectID: self,
            address: address,
            data: &pid,
            dataSize: UInt32(MemoryLayout<pid_t>.size)
        )
        return pid
    }

    func readProcessBundleID() throws -> String? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bundleID: CFString?
        try withUnsafeMutablePointer(to: &bundleID) { pointer in
            try Self.readPropertyData(
                objectID: self,
                address: address,
                data: UnsafeMutableRawPointer(pointer),
                dataSize: UInt32(MemoryLayout<CFString?>.size)
            )
        }
        return bundleID as String?
    }

    private static func readPropertyDataSize(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) throws -> UInt32 {
        var mutableAddress = address
        var dataSize: UInt32 = 0
        try checkOSStatus(
            AudioObjectGetPropertyDataSize(objectID, &mutableAddress, 0, nil, &dataSize),
            "AudioObjectGetPropertyDataSize(\(address.mSelector))"
        )
        return dataSize
    }

    private static func readPropertyData(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        data: UnsafeMutableRawPointer,
        dataSize: UInt32
    ) throws {
        var mutableAddress = address
        var mutableDataSize = dataSize
        try checkOSStatus(
            AudioObjectGetPropertyData(
                objectID,
                &mutableAddress,
                0,
                nil,
                &mutableDataSize,
                data
            ),
            "AudioObjectGetPropertyData(\(address.mSelector))"
        )
    }
}
