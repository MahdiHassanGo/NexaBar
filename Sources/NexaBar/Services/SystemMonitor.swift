import Foundation
import Darwin

struct SystemSnapshot {
    let cpuPercent: Double
    let memoryPercent: Double
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let diskPercent: Double
    let diskUsedGB: Double
    let diskTotalGB: Double
    let cpuTemperature: Double?
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

final class SystemMonitor: @unchecked Sendable {
    private let hostPort: mach_port_t = mach_host_self()
    private let totalPhysicalMemory = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64

    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0

    private var previousNetworkIn: UInt64 = 0
    private var previousNetworkOut: UInt64 = 0
    private var previousNetworkTime: CFAbsoluteTime = 0

    private let activeTemperatureKeys: [String]

    init() {
        var size: vm_size_t = 4096
        host_page_size(hostPort, &size)
        pageSize = UInt64(size)
        activeTemperatureKeys = TemperatureScanner.discoverActiveKeys()
    }

    deinit {
        if let previousCPUInfo {
            let bytes = MemoryLayout<integer_t>.size * Int(previousCPUInfoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCPUInfo), vm_size_t(bytes))
        }
    }

    func snapshot() -> SystemSnapshot {
        let cpu = readCPUPercent()
        let memory = readMemory()
        let disk = readDisk()
        let network = readNetwork()
        let temperature = readTemperature()

        return SystemSnapshot(
            cpuPercent: cpu,
            memoryPercent: memory.percent,
            memoryUsedGB: memory.usedGB,
            memoryTotalGB: memory.totalGB,
            diskPercent: disk.percent,
            diskUsedGB: disk.usedGB,
            diskTotalGB: disk.totalGB,
            cpuTemperature: temperature,
            downloadBytesPerSecond: network.down,
            uploadBytesPerSecond: network.up
        )
    }

    private func readCPUPercent() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }
        defer {
            if previousCPUInfo == nil {
                // Keep current sample as the previous sample below.
            }
        }

        var percentage = 0.0

        if let old = previousCPUInfo {
            var active: UInt64 = 0
            var total: UInt64 = 0

            for index in 0..<Int(cpuCount) {
                let offset = Int(CPU_STATE_MAX) * index

                let user = max(0, cpuInfo[offset + Int(CPU_STATE_USER)] - old[offset + Int(CPU_STATE_USER)])
                let system = max(0, cpuInfo[offset + Int(CPU_STATE_SYSTEM)] - old[offset + Int(CPU_STATE_SYSTEM)])
                let nice = max(0, cpuInfo[offset + Int(CPU_STATE_NICE)] - old[offset + Int(CPU_STATE_NICE)])
                let idle = max(0, cpuInfo[offset + Int(CPU_STATE_IDLE)] - old[offset + Int(CPU_STATE_IDLE)])

                active += UInt64(user + system + nice)
                total += UInt64(user + system + nice + idle)
            }

            if total > 0 {
                percentage = Double(active) / Double(total) * 100
            }

            let oldBytes = MemoryLayout<integer_t>.size * Int(previousCPUInfoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: old), vm_size_t(oldBytes))
        }

        previousCPUInfo = cpuInfo
        previousCPUInfoCount = cpuInfoCount
        return min(max(percentage, 0), 100)
    }

    private func readMemory() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = totalPhysicalMemory
        let percent = total > 0 ? Double(used) / Double(total) * 100 : 0

        return (
            min(max(percent, 0), 100),
            Double(used) / 1_073_741_824,
            Double(total) / 1_073_741_824
        )
    }

    private func readDisk() -> (percent: Double, usedGB: Double, totalGB: Double) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let totalNumber = attributes[.systemSize] as? NSNumber,
              let freeNumber = attributes[.systemFreeSize] as? NSNumber else {
            return (0, 0, 0)
        }

        let total = totalNumber.uint64Value
        let free = freeNumber.uint64Value
        let used = total > free ? total - free : 0
        let percent = total > 0 ? Double(used) / Double(total) * 100 : 0

        return (
            min(max(percent, 0), 100),
            Double(used) / 1_073_741_824,
            Double(total) / 1_073_741_824
        )
    }

    private func readNetwork() -> (down: Double, up: Double) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUsable = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 && (flags & IFF_LOOPBACK) == 0

            if isUsable,
               let address = current.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let namePointer = current.pointee.ifa_name,
               let dataPointer = current.pointee.ifa_data {
                let name = String(cString: namePointer)

                // macOS normally uses en0/en1/... for Wi‑Fi and Ethernet.
                // Restricting to these avoids counting loopback/tunnels twice.
                if name.hasPrefix("en") {
                    let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                    input += UInt64(data.ifi_ibytes)
                    output += UInt64(data.ifi_obytes)
                }
            }

            pointer = current.pointee.ifa_next
        }

        let now = CFAbsoluteTimeGetCurrent()
        var down = 0.0
        var up = 0.0

        if previousNetworkTime > 0 {
            let elapsed = now - previousNetworkTime
            if elapsed > 0 {
                let deltaIn = input >= previousNetworkIn ? input - previousNetworkIn : 0
                let deltaOut = output >= previousNetworkOut ? output - previousNetworkOut : 0
                down = Double(deltaIn) / elapsed
                up = Double(deltaOut) / elapsed
            }
        }

        previousNetworkIn = input
        previousNetworkOut = output
        previousNetworkTime = now

        return (down, up)
    }

    private func readTemperature() -> Double? {
        guard !activeTemperatureKeys.isEmpty else { return nil }

        let values = activeTemperatureKeys.compactMap { key -> Double? in
            guard let value = SMC.shared.getValue(key), value > 15, value < 110 else { return nil }
            return value
        }

        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum TemperatureScanner {
    static func discoverActiveKeys() -> [String] {
        let keys = [
            // Apple Silicon general / cluster keys
            "Tc0a", "Tc0b", "Tc0x", "Tc0z", "Tc1a", "Tc1b", "Tc1x", "Tc1z",
            "Tc2a", "Tc2b", "Tc2x", "Tc2z", "Tc3a", "Tc3b", "Tc3x", "Tc3z",
            "Tc4a", "Tc4b", "Tc4x", "Tc4z", "Tc5a", "Tc5b", "Tc5x", "Tc5z",
            "Te05", "Te06", "Te09", "Te0H", "Te0L", "Te0P", "Te0S", "Te0T",
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",

            // Intel fallbacks
            "TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C", "TC9C",
            "TC0D", "TC0P", "TC0H"
        ]

        return keys.filter { key in
            guard let value = SMC.shared.getValue(key) else { return false }
            return value > 15 && value < 110
        }
    }
}
