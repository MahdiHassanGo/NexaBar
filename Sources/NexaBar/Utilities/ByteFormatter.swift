import Foundation

enum ByteFormatter {
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fG/s", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM/s", value / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK/s", value / 1_000)
        default:
            return String(format: "%.0fB/s", value)
        }
    }

    static func gigabytes(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f GB", value) }
        return String(format: "%.1f GB", value)
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }
}
