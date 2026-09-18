import Foundation
import IOKit

// Low-level AppleSMC reader. See THIRD_PARTY_NOTICES.md for attribution.

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    )
}

private struct SMCValue {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
}

private extension FourCharCode {
    init(smcString: String) {
        precondition(smcString.utf8.count == 4)
        self = smcString.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    var smcString: String {
        let scalars = [24, 16, 8, 0].compactMap { shift -> UnicodeScalar? in
            UnicodeScalar((self >> UInt32(shift)) & 0xff)
        }
        return scalars.count == 4 ? scalars.map { String($0) }.joined() : "????"
    }
}

final class SMC: @unchecked Sendable {
    static let shared = SMC()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private init() {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleSMC") else { return }

        let matchResult = IOServiceGetMatchingServices(0, matching, &iterator)
        guard matchResult == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }

        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            connection = 0
            return
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func getValue(_ key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var value = SMCValue(key: key)
        guard read(&value) == kIOReturnSuccess else { return nil }
        guard value.dataSize > 0 else { return nil }

        switch value.dataType {
        case "ui8 ":
            return Double(value.bytes[0])
        case "ui16":
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw)
        case "ui32":
            let raw = UInt32(value.bytes[0]) << 24 |
                      UInt32(value.bytes[1]) << 16 |
                      UInt32(value.bytes[2]) << 8 |
                      UInt32(value.bytes[3])
            return Double(raw)
        case "sp78":
            let signed = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(signed) / 256.0
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            let bits = UInt32(value.bytes[0]) |
                       UInt32(value.bytes[1]) << 8 |
                       UInt32(value.bytes[2]) << 16 |
                       UInt32(value.bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        default:
            if value.dataSize == 4 {
                let bits = UInt32(value.bytes[0]) |
                           UInt32(value.bytes[1]) << 8 |
                           UInt32(value.bytes[2]) << 16 |
                           UInt32(value.bytes[3]) << 24
                let possible = Double(Float(bitPattern: bits))
                return possible.isFinite ? possible : nil
            }
            return nil
        }
    }

    private func read(_ value: inout SMCValue) -> kern_return_t {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(smcString: value.key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        var result = call(SMCCommand.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        value.dataSize = UInt32(output.keyInfo.dataSize)
        value.dataType = output.keyInfo.dataType.smcString
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue

        result = call(SMCCommand.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        withUnsafeBytes(of: output.bytes) { raw in
            let count = min(Int(value.dataSize), 32, raw.count)
            if count > 0 {
                value.bytes.replaceSubrange(0..<count, with: raw.prefix(count))
            }
        }
        return kIOReturnSuccess
    }

    private func call(_ index: UInt8, input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(index),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}
