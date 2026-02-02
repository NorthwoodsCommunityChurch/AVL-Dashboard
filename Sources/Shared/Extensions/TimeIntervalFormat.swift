import Foundation

public extension TimeInterval {
    /// Formats seconds into human-readable uptime like "3d 14h 22m".
    var formattedUptime: String {
        let totalSeconds = Int(self)
        guard totalSeconds >= 0 else { return "0m" }

        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

public extension Double {
    /// Formats bytes per second into a compact string like "1.2 KB/s" or "45 MB/s".
    var formattedBytesPerSec: String {
        if self < 1024 {
            return "\(Int(self)) B/s"
        } else if self < 1024 * 1024 {
            return String(format: "%.0f KB/s", self / 1024)
        } else {
            return String(format: "%.1f MB/s", self / (1024 * 1024))
        }
    }
}
