import Foundation

public struct MachineThresholds: Codable, Sendable, Equatable {
    public var good: Double
    public var warning: Double
    public var critical: Double

    public static let defaults = MachineThresholds(good: 50, warning: 70, critical: 90)

    public init(good: Double, warning: Double, critical: Double) {
        self.good = good
        self.warning = warning
        self.critical = critical
    }

    /// Clamp values to a reasonable range.
    public mutating func validate(maxValue: Double = 150) {
        good = min(max(good, 0), maxValue)
        warning = min(max(warning, good), maxValue)
        critical = min(max(critical, warning), maxValue)
    }
}
