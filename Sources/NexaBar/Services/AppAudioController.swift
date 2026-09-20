import AppKit
import AudioToolbox
import CoreGraphics
import CoreAudio
import Darwin
import Foundation
import Accelerate

struct AppAudioItem: Identifiable, Equatable {
    let id: String
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    var volume: Double
    var isMuted: Bool
    let pid: pid_t
    let processObjectIDs: [AudioObjectID]

    static func == (lhs: AppAudioItem, rhs: AppAudioItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.volume == rhs.volume &&
        lhs.isMuted == rhs.isMuted &&
        lhs.processObjectIDs == rhs.processObjectIDs
    }
}

/// Real per-application volume control using Apple's public Core Audio Process Tap API.
/// Models FineTune's CoreAudio engine and safety filters.
final class AppAudioController: @unchecked Sendable {
    private let engine = PerAppAudioEngine()
    private let controlQueue = DispatchQueue(label: "com.nexabar.per-app-audio", qos: .userInitiated)

    /// Check if system audio capture (Screen & System Audio Recording) permission is granted.
    private typealias PreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int

    static func hasAudioCapturePermission() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let sym = dlsym(handle, "TCCAccessPreflight") else {
            return true
        }
        let preflight = unsafeBitCast(sym, to: PreflightFunc.self)
        let result = preflight("kTCCServiceAudioCapture" as CFString, nil)
        // 0 = authorized, 1 = denied, -1 = unknown
        return result != 1
    }

    func getRunningAudioApps(existingItems: [AppAudioItem]) -> [AppAudioItem] {
        let existingMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.bundleIdentifier, $0) })
        let savedVolumes = UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]
        let savedMutes = UserDefaults.standard.dictionary(forKey: "appMutes") as? [String: Bool] ?? [:]

        let runningApps = NSWorkspace.shared.runningApplications
        let appsByPID = Dictionary(
            runningApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var grouped: [pid_t: AudioAppGroup] = [:]
        let myPID = ProcessInfo.processInfo.processIdentifier

        for objectID in readAudioProcessList() {
            guard let pid = readPID(for: objectID), pid != myPID else { continue }
            guard readIsRunningOutput(for: objectID) else { continue }

            let resolved = resolveOwningApplication(for: pid, appsByPID: appsByPID)
            let ownerPID = resolved?.processIdentifier ?? pid

            let rawBundleID = resolved?.bundleIdentifier ?? readBundleID(for: objectID)
            let name = resolved?.localizedName
                ?? rawBundleID?.components(separatedBy: ".").last
                ?? "Audio App"

            // Skip system daemons, coreaudiod, siri, system sounds, etc. to prevent muting main system audio.
            if isSystemDaemon(bundleID: rawBundleID, name: name) {
                continue
            }

            let bundleID = rawBundleID ?? "audio-process-\(ownerPID)"
            if bundleID == Bundle.main.bundleIdentifier || bundleID == "com.nexabar.app" {
                continue
            }

            let icon = resolved?.icon
                ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: name)
                ?? NSImage()

            if var existing = grouped[ownerPID] {
                if !existing.processObjectIDs.contains(objectID) {
                    existing.processObjectIDs.append(objectID)
                    existing.processObjectIDs.sort()
                    grouped[ownerPID] = existing
                }
            } else {
                grouped[ownerPID] = AudioAppGroup(
                    pid: ownerPID,
                    bundleIdentifier: bundleID,
                    name: name,
                    icon: icon,
                    processObjectIDs: [objectID]
                )
            }
        }

        let items = grouped.values.map { group -> AppAudioItem in
            let existing = existingMap[group.bundleIdentifier]
            return AppAudioItem(
                id: group.bundleIdentifier,
                bundleIdentifier: group.bundleIdentifier,
                name: group.name,
                icon: group.icon,
                volume: existing?.volume ?? savedVolumes[group.bundleIdentifier] ?? 1.0,
                isMuted: existing?.isMuted ?? savedMutes[group.bundleIdentifier] ?? false,
                pid: group.pid,
                processObjectIDs: group.processObjectIDs
            )
        }

        return items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func setAppVolume(
        app: AppAudioItem,
        volume: Double,
        completion: (@Sendable (String?) -> Void)? = nil
    ) {
        let safeVolume = min(max(volume, 0), 1)
        var savedVolumes = UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]
        savedVolumes[app.bundleIdentifier] = safeVolume
        UserDefaults.standard.set(savedVolumes, forKey: "appVolumes")

        let key = app.bundleIdentifier
        let name = app.name
        let objectIDs = app.processObjectIDs
        let muted = app.isMuted

        controlQueue.async { [engine] in
            do {
                try engine.apply(
                    key: key,
                    appName: name,
                    processObjectIDs: objectIDs,
                    volume: safeVolume,
                    muted: muted
                )
                completion?(nil)
            } catch {
                completion?(Self.friendlyError(error))
            }
        }
    }

    func setAppMute(
        app: AppAudioItem,
        isMuted: Bool,
        completion: (@Sendable (String?) -> Void)? = nil
    ) {
        var savedMutes = UserDefaults.standard.dictionary(forKey: "appMutes") as? [String: Bool] ?? [:]
        savedMutes[app.bundleIdentifier] = isMuted
        UserDefaults.standard.set(savedMutes, forKey: "appMutes")

        let savedVolumes = UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double] ?? [:]
        let currentVolume = savedVolumes[app.bundleIdentifier] ?? app.volume
        let key = app.bundleIdentifier
        let name = app.name
        let objectIDs = app.processObjectIDs

        controlQueue.async { [engine] in
            do {
                try engine.apply(
                    key: key,
                    appName: name,
                    processObjectIDs: objectIDs,
                    volume: currentVolume,
                    muted: isMuted
                )
                completion?(nil)
            } catch {
                completion?(Self.friendlyError(error))
            }
        }
    }

    /// Keeps active taps in sync when processes restart or default output changes.
    func synchronize(apps: [AppAudioItem]) {
        let snapshots = apps.map {
            AudioAppSnapshot(
                key: $0.bundleIdentifier,
                name: $0.name,
                processObjectIDs: $0.processObjectIDs,
                volume: $0.volume,
                muted: $0.isMuted
            )
        }

        controlQueue.async { [engine] in
            engine.synchronize(with: snapshots)
        }
    }

    func stop() {
        controlQueue.sync { [engine] in
            engine.stopAll()
        }
    }

    private static func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "NexaBar.PerAppAudio", nsError.code == PerAppAudioError.unsupported.rawValue {
            return "Per-app volume requires macOS 14.2 or newer."
        }
        return "Per-app audio needs Screen & System Audio Recording permission. Enable NexaBar in System Settings → Privacy & Security → Screen & System Audio Recording."
    }

    // MARK: - System Daemons Exclusion (FineTune Rules)

    private static let systemDaemonPrefixes: [String] = [
        "com.apple.siri",
        "com.apple.Siri",
        "com.apple.assistant",
        "com.apple.audio",
        "com.apple.coreaudio",
        "com.apple.mediaremote",
        "com.apple.accessibility.heard",
        "com.apple.hearingd",
        "com.apple.voicebankingd",
        "com.apple.systemsound",
        "com.apple.FrontBoardServices",
        "com.apple.frontboard",
        "com.apple.springboard",
        "com.apple.notificationcenter",
        "com.apple.NotificationCenter",
        "com.apple.UserNotifications",
        "com.apple.usernotifications",
        "com.apple.SpeechRecognitionCore",
        "com.apple.speech",
        "com.apple.dictation",
        "com.apple.corespeech",
        "com.apple.CoreSpeech",
        "com.apple.VoiceControl",
        "com.apple.voicecontrol",
        "com.apple.sound",
        "com.apple.WebKit",
    ]

    private static let systemDaemonNames: [String] = [
        "systemsoundserverd",
        "systemsoundserv",
        "coreaudiod",
        "audiomxd",
        "speechrecognitiond",
        "dictationd",
        "corespeech",
        "launchd",
    ]

    private func isSystemDaemon(bundleID: String?, name: String) -> Bool {
        if let bundleID {
            if Self.systemDaemonPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return true
            }
        }
        let lowerName = name.lowercased()
        if Self.systemDaemonNames.contains(where: { lowerName.hasPrefix($0) }) {
            return true
        }
        return false
    }

    // MARK: - Audio process discovery

    private func readAudioProcessList() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private func readPID(for objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid) == noErr,
              pid > 0 else { return nil }
        return pid
    }

    private func readIsRunningOutput(for objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private func readBundleID(for objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    // MARK: - Process Responsibility Resolution (FineTune Helper Mapping)

    private typealias ResponsibilityFunc = @convention(c) (pid_t) -> pid_t

    private static let cachedResponsibilityFunc: ResponsibilityFunc? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunc.self)
    }()

    private func getResponsiblePID(for pid: pid_t) -> pid_t? {
        guard let fn = Self.cachedResponsibilityFunc else { return nil }
        let responsiblePID = fn(pid)
        return responsiblePID > 0 && responsiblePID != pid ? responsiblePID : nil
    }

    private func resolveOwningApplication(
        for pid: pid_t,
        appsByPID: [pid_t: NSRunningApplication]
    ) -> NSRunningApplication? {
        // 1. Try responsibility API (Safari WebKit, Chrome Renderer, Discord Helper)
        if let responsiblePID = getResponsiblePID(for: pid),
           let app = appsByPID[responsiblePID],
           app.bundleURL?.pathExtension.lowercased() == "app" {
            return app
        }

        // 2. Process tree walking via sysctl
        var currentPID = pid
        var visited = Set<pid_t>()

        while currentPID > 1 && !visited.contains(currentPID) {
            visited.insert(currentPID)

            if let app = appsByPID[currentPID],
               app.bundleURL?.pathExtension.lowercased() == "app" {
                return app
            }

            guard let parent = parentPID(of: currentPID), parent != currentPID else { break }
            currentPID = parent
        }
        return appsByPID[pid]
    }

    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}

private struct AudioAppGroup {
    let pid: pid_t
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    var processObjectIDs: [AudioObjectID]
}

private struct AudioAppSnapshot: Sendable {
    let key: String
    let name: String
    let processObjectIDs: [AudioObjectID]
    let volume: Double
    let muted: Bool
}

private enum PerAppAudioError: Int, Error {
    case unsupported = 1
    case noOutputDevice = 2
    case processTapCreationFailed = 3
    case aggregateCreationFailed = 4
    case ioProcCreationFailed = 5
    case deviceStartFailed = 6
    case permissionDenied = 7
}

/// Core Audio process-tap engine inspired by FineTune.
private final class PerAppAudioEngine: @unchecked Sendable {
    private var sessions: [String: PerAppAudioSession] = [:]

    func apply(
        key: String,
        appName: String,
        processObjectIDs: [AudioObjectID],
        volume: Double,
        muted: Bool
    ) throws {
        guard !processObjectIDs.isEmpty else {
            stop(key: key)
            return
        }

        // At 100% and unmuted, return audio back to native Core Audio hardware and destroy tap.
        if volume >= 0.999 && !muted {
            stop(key: key)
            return
        }

        // Require TCC Screen & System Audio Recording permission before tapping
        guard AppAudioController.hasAudioCapturePermission() else {
            stop(key: key)
            throw PerAppAudioError.permissionDenied
        }

        guard let outputUID = currentDefaultOutputUID() else {
            throw PerAppAudioError.noOutputDevice
        }

        if let session = sessions[key],
           session.processObjectIDs == processObjectIDs,
           session.outputUID == outputUID {
            session.set(volume: volume, muted: muted)
            return
        }

        stop(key: key)

        let session = try PerAppAudioSession(
            appName: appName,
            processObjectIDs: processObjectIDs,
            outputUID: outputUID,
            volume: volume,
            muted: muted
        )
        sessions[key] = session
    }

    func synchronize(with apps: [AudioAppSnapshot]) {
        let map = Dictionary(uniqueKeysWithValues: apps.map { ($0.key, $0) })
        let activeKeys = Array(sessions.keys)

        for key in activeKeys {
            guard let app = map[key] else {
                stop(key: key)
                continue
            }

            do {
                try apply(
                    key: app.key,
                    appName: app.name,
                    processObjectIDs: app.processObjectIDs,
                    volume: app.volume,
                    muted: app.muted
                )
            } catch {
                stop(key: key)
            }
        }

        // Re-apply saved sub-100%/mute state when an audio-producing app appears
        for app in apps where sessions[app.key] == nil && (app.volume < 0.999 || app.muted) {
            try? apply(
                key: app.key,
                appName: app.name,
                processObjectIDs: app.processObjectIDs,
                volume: app.volume,
                muted: app.muted
            )
        }
    }

    func stopAll() {
        let all = sessions.values
        sessions.removeAll()
        for session in all {
            session.stop()
        }
    }

    private func stop(key: String) {
        guard let session = sessions.removeValue(forKey: key) else { return }
        session.stop()
    }

    private func currentDefaultOutputUID() -> String? {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let system = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}

/// Encapsulates process tap → aggregate device → IOProc callback.
/// Follows FineTune's TapResources async teardown order.
private final class PerAppAudioSession: @unchecked Sendable {
    let processObjectIDs: [AudioObjectID]
    let outputUID: String

    private let callbackQueue: DispatchQueue
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?

    private var targetGain: Float
    private var currentGain: Float
    private var stopped = false

    init(
        appName: String,
        processObjectIDs: [AudioObjectID],
        outputUID: String,
        volume: Double,
        muted: Bool
    ) throws {
        self.processObjectIDs = processObjectIDs.sorted()
        self.outputUID = outputUID
        let initial = muted ? Float(0) : Float(min(max(volume, 0), 1))
        self.targetGain = initial
        self.currentGain = initial
        self.callbackQueue = DispatchQueue(
            label: "com.nexabar.audio-tap.\(appName.replacingOccurrences(of: " ", with: "-"))",
            qos: .userInteractive
        )

        do {
            try start(appName: appName)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func set(volume: Double, muted: Bool) {
        targetGain = muted ? 0 : Float(min(max(volume, 0), 1))
    }

    func stop() {
        if stopped { return }
        stopped = true

        let localAggregate = aggregateID
        let localTap = tapID
        let localProc = ioProcID

        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown

        // FineTune TapResources async background teardown sequence
        DispatchQueue.global(qos: .utility).async {
            if localAggregate != kAudioObjectUnknown, let localProc {
                _ = AudioDeviceStop(localAggregate, localProc)
                _ = AudioDeviceDestroyIOProcID(localAggregate, localProc)
            }
            if localAggregate != kAudioObjectUnknown {
                _ = AudioHardwareDestroyAggregateDevice(localAggregate)
            }
            if localTap != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(localTap)
            }
        }
    }

    private func start(appName: String) throws {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.uuid = UUID()
        tapDescription.name = "NexaBar \(appName)"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else {
            throw NSError(
                domain: "NexaBar.PerAppAudio",
                code: PerAppAudioError.processTapCreationFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateProcessTap failed: \(tapStatus)"]
            )
        }
        tapID = newTapID

        // Single output device aggregate: isStacked = false (matching FineTune buildAggregateDescription)
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NexaBar-\(appName)-\(UUID().uuidString.prefix(8))",
            kAudioAggregateDeviceUIDKey: "com.nexabar.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: false
                ]
            ]
        ]

        var newAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard aggregateStatus == noErr else {
            throw NSError(
                domain: "NexaBar.PerAppAudio",
                code: PerAppAudioError.aggregateCreationFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateAggregateDevice failed: \(aggregateStatus)"]
            )
        }
        aggregateID = newAggregateID

        guard waitUntilReady(deviceID: newAggregateID) else {
            throw NSError(
                domain: "NexaBar.PerAppAudio",
                code: PerAppAudioError.aggregateCreationFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Private aggregate device did not become ready"]
            )
        }

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID,
            newAggregateID,
            callbackQueue
        ) { @Sendable [weak self] _, inputData, _, outputData, _ in
            guard let self else {
                Self.zero(outputData)
                return
            }
            self.render(inputData: inputData, outputData: outputData)
        }

        guard procStatus == noErr, let newProcID else {
            throw NSError(
                domain: "NexaBar.PerAppAudio",
                code: PerAppAudioError.ioProcCreationFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "AudioDeviceCreateIOProcIDWithBlock failed: \(procStatus)"]
            )
        }
        ioProcID = newProcID

        let startStatus = AudioDeviceStart(newAggregateID, newProcID)
        guard startStatus == noErr else {
            throw NSError(
                domain: "NexaBar.PerAppAudio",
                code: PerAppAudioError.deviceStartFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "AudioDeviceStart failed: \(startStatus)"]
            )
        }
    }

    private func waitUntilReady(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        for _ in 0..<50 {
            var size: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 {
                return true
            }
            usleep(20_000)
        }
        return false
    }

    nonisolated private func render(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)

        guard !inputs.isEmpty, !outputs.isEmpty else {
            Self.zero(outputData)
            return
        }

        let inputCount = inputs.count
        let outputCount = outputs.count
        var gain = currentGain
        let target = targetGain
        let ramp: Float = 0.0015 // 30ms ramp smoothing for 48kHz audio (FineTune ramp)
        let isMutedOrZero = target <= 0.0001 && gain <= 0.0001
        let isSteadyGain = abs(target - gain) < 0.0001

        for outputIndex in 0..<outputCount {
            let outputBuffer = outputs[outputIndex]
            guard let outputRaw = outputBuffer.mData else { continue }

            let inputIndex = inputCount > outputCount
                ? inputCount - outputCount + outputIndex
                : outputIndex

            guard inputIndex >= 0, inputIndex < inputCount,
                  let inputRaw = inputs[inputIndex].mData else {
                memset(outputRaw, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputBuffer = inputs[inputIndex]
            let inputChannels = max(1, Int(inputBuffer.mNumberChannels))
            let outputChannels = max(1, Int(outputBuffer.mNumberChannels))
            let inputSamples = inputRaw.assumingMemoryBound(to: Float.self)
            let outputSamples = outputRaw.assumingMemoryBound(to: Float.self)
            let inputSampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let outputSampleCount = Int(outputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = min(inputSampleCount / inputChannels, outputSampleCount / outputChannels)

            guard frameCount > 0 else {
                memset(outputRaw, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            if isMutedOrZero {
                memset(outputRaw, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let totalSamples = frameCount * outputChannels

            if inputChannels == outputChannels {
                if isSteadyGain {
                    var sGain = target
                    vDSP_vsmul(inputSamples, 1, &sGain, outputSamples, 1, vDSP_Length(totalSamples))
                    gain = target
                } else {
                    for frame in 0..<frameCount {
                        gain += (target - gain) * ramp
                        let base = frame * outputChannels
                        for channel in 0..<outputChannels {
                            outputSamples[base + channel] = inputSamples[base + channel] * gain
                        }
                    }
                }
            } else if inputChannels == 2 && outputChannels >= 2 {
                if isSteadyGain {
                    let sGain = target
                    let inSamples2 = inputSamples
                    for frame in 0..<frameCount {
                        let inBase = frame * 2
                        let outBase = frame * outputChannels
                        outputSamples[outBase] = inSamples2[inBase] * sGain
                        outputSamples[outBase + 1] = inSamples2[inBase + 1] * sGain
                        for ch in 2..<outputChannels {
                            outputSamples[outBase + ch] = 0
                        }
                    }
                    gain = target
                } else {
                    for frame in 0..<frameCount {
                        gain += (target - gain) * ramp
                        let inBase = frame * 2
                        let outBase = frame * outputChannels
                        for channel in 0..<outputChannels {
                            outputSamples[outBase + channel] = 0
                        }
                        outputSamples[outBase] = inputSamples[inBase] * gain
                        outputSamples[outBase + 1] = inputSamples[inBase + 1] * gain
                    }
                }
            } else {
                let copiedChannels = min(inputChannels, outputChannels)
                for frame in 0..<frameCount {
                    gain += (target - gain) * ramp
                    let inBase = frame * inputChannels
                    let outBase = frame * outputChannels
                    for channel in 0..<outputChannels {
                        outputSamples[outBase + channel] = channel < copiedChannels
                            ? inputSamples[inBase + channel] * gain
                            : 0
                    }
                }
            }

            if totalSamples < outputSampleCount {
                memset(
                    outputSamples.advanced(by: totalSamples),
                    0,
                    (outputSampleCount - totalSamples) * MemoryLayout<Float>.size
                )
            }
        }

        currentGain = gain
    }


    nonisolated private static func zero(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in outputs {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }
}
