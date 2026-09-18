import Foundation
import CoreAudio
import AudioToolbox
import AppKit

struct AudioDeviceItem: Identifiable, Equatable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    var volume: Double // 0.0 ... 1.0
    var isMuted: Bool
    var isDefaultOutput: Bool

    var iconName: String {
        let lower = name.lowercased()
        if lower.contains("headphone") || lower.contains("hifi") || lower.contains("airpod") || lower.contains("ear") || lower.contains("buds") {
            return "headphones"
        } else if lower.contains("speaker") || lower.contains("macbook") || lower.contains("internal") {
            return "laptopcomputer"
        } else if lower.contains("tv") || lower.contains("display") || lower.contains("hdmi") || lower.contains("monitor") {
            return "tv"
        } else if lower.contains("teams") || lower.contains("discord") || lower.contains("zoom") || lower.contains("music") {
            return "app.badge"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

final class AudioController: @unchecked Sendable {
    func getOutputDevices() -> [AudioDeviceItem] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return getFallbackState() }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)

        let defaultOutputID = getDefaultOutputDeviceID()
        var devices: [AudioDeviceItem] = []

        for id in deviceIDs {
            guard hasOutputChannels(deviceID: id) else { continue }
            guard let name = getDeviceName(deviceID: id), !name.isEmpty else { continue }
            let uid = getDeviceUID(deviceID: id) ?? "\(id)"

            let vol = getDeviceVolume(deviceID: id)
            let mute = getDeviceMute(deviceID: id)
            let isDefault = (id == defaultOutputID)

            devices.append(AudioDeviceItem(
                id: id,
                uid: uid,
                name: name,
                volume: vol,
                isMuted: mute,
                isDefaultOutput: isDefault
            ))
        }

        if devices.isEmpty {
            return getFallbackState()
        }

        return devices
    }

    func setDefaultOutputDevice(id: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &deviceID)
    }

    func setDeviceVolume(deviceID: AudioObjectID, volume: Double) {
        let vol = Float32(min(max(volume, 0.0), 1.0))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let size = UInt32(MemoryLayout<Float32>.size)
        var v = vol
        if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &v) != noErr {
            address.mElement = 1
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &v)
        }
        
        if deviceID == getDefaultOutputDeviceID() {
            setSystemVolumeScript(volume)
        }
    }

    func toggleDeviceMute(deviceID: AudioObjectID, currentMute: Bool) {
        var mute: UInt32 = currentMute ? 0 : 1
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mute) != noErr {
            address.mElement = 1
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mute)
        }
        
        if deviceID == getDefaultOutputDeviceID() {
            setSystemMuteScript(!currentMute)
        }
    }

    private func getDefaultOutputDeviceID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func hasOutputChannels(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else { return false }

        let numberBuffers = Int(bufferListPointer.pointee.mNumberBuffers)
        if numberBuffers == 0 { return false }

        var channelCount: UInt32 = 0
        withUnsafePointer(to: &bufferListPointer.pointee.mBuffers) { pBuffers in
            for i in 0..<numberBuffers {
                channelCount += pBuffers.advanced(by: i).pointee.mNumberChannels
            }
        }
        return channelCount > 0
    }

    private func getDeviceName(deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        if status == noErr, let unmanagedName = name {
            return unmanagedName.takeUnretainedValue() as String
        }
        return nil
    }

    private func getDeviceUID(deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        if status == noErr, let unmanagedUID = uid {
            return unmanagedUID.takeUnretainedValue() as String
        }
        return nil
    }

    private func getDeviceVolume(deviceID: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol) != noErr {
            address.mElement = 1
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol) != noErr {
                // Fallback to script if CoreAudio volume getter fails
                return getSystemVolumeScript()
            }
        }
        return min(max(Double(vol), 0.0), 1.0)
    }

    private func getDeviceMute(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute) != noErr {
            address.mElement = 1
            _ = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        }
        return mute != 0
    }

    private func getFallbackState() -> [AudioDeviceItem] {
        let vol = getSystemVolumeScript()
        return [AudioDeviceItem(
            id: 1,
            uid: "default",
            name: "Mac Audio Output",
            volume: vol,
            isMuted: false,
            isDefaultOutput: true
        )]
    }

    private func getSystemVolumeScript() -> Double {
        guard let volumeText = runAppleScript("output volume of (get volume settings)"),
              let vol = Double(volumeText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0.5
        }
        return vol / 100.0
    }

    private func setSystemVolumeScript(_ volume: Double) {
        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        _ = runAppleScript("set volume output volume \(percent)")
    }

    private func setSystemMuteScript(_ muted: Bool) {
        _ = runAppleScript("set volume output muted \(muted ? "true" : "false")")
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
