import Foundation

/// Persisted record for a known machine. Keyed by hardwareUUID.
public struct MachineIdentity: Codable, Identifiable, Sendable {
    public var id: String { hardwareUUID }
    public let hardwareUUID: String
    public var lastKnownHostname: String
    public var displayName: String
    public var thresholds: MachineThresholds
    public var lastSeen: Date
    public var manualEndpoint: String?

    public init(hardwareUUID: String, hostname: String) {
        self.hardwareUUID = hardwareUUID
        self.lastKnownHostname = hostname
        self.displayName = hostname
        self.thresholds = .defaults
        self.lastSeen = Date()
        self.manualEndpoint = nil
    }
}
