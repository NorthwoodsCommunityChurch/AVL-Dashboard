import Foundation

/// Global dashboard settings persisted alongside machine data.
public struct DashboardSettings: Codable, Sendable, Equatable {
    public var tempThresholds: MachineThresholds
    public var cpuThresholds: MachineThresholds

    public static let defaults = DashboardSettings(
        tempThresholds: MachineThresholds(good: 50, warning: 70, critical: 90),
        cpuThresholds: MachineThresholds(good: 30, warning: 60, critical: 90)
    )

    public init(tempThresholds: MachineThresholds, cpuThresholds: MachineThresholds) {
        self.tempThresholds = tempThresholds
        self.cpuThresholds = cpuThresholds
    }

    public mutating func validate() {
        tempThresholds.validate(maxValue: 150)
        cpuThresholds.validate(maxValue: 100)
    }
}
