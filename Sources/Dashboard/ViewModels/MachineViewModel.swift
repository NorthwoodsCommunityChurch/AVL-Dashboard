import Foundation
import Observation
import Shared

@Observable
final class MachineViewModel: Identifiable {
    let hardwareUUID: String
    var displayName: String
    var hostname: String
    var thresholds: MachineThresholds

    var isOnline: Bool = false
    var cpuTemp: Double = -1
    var cpuUsage: Double = 0
    var networkBytesPerSec: Double = 0
    var uptimeSeconds: TimeInterval = 0
    var networkInfo: NetworkInfo?
    var fileVaultEnabled: Bool = false
    var lastSeen: Date

    var manualEndpoint: String?
    var isBonjourActive: Bool = false

    var isFlipped: Bool = false
    var consecutiveFailures: Int = 0

    var isManual: Bool { manualEndpoint != nil }
    var id: String { hardwareUUID }

    init(from identity: MachineIdentity) {
        self.hardwareUUID = identity.hardwareUUID
        self.displayName = identity.displayName
        self.hostname = identity.lastKnownHostname
        self.thresholds = identity.thresholds
        self.lastSeen = identity.lastSeen
        self.manualEndpoint = identity.manualEndpoint
    }

    init(from status: MachineStatus) {
        self.hardwareUUID = status.hardwareUUID
        self.displayName = status.hostname
        self.hostname = status.hostname
        self.thresholds = .defaults
        self.lastSeen = Date()
        self.manualEndpoint = nil
        update(from: status)
    }

    func update(from status: MachineStatus) {
        cpuTemp = status.cpuTempCelsius
        cpuUsage = status.cpuUsagePercent
        networkBytesPerSec = status.networkBytesPerSec
        uptimeSeconds = status.uptimeSeconds
        hostname = status.hostname
        networkInfo = status.network
        fileVaultEnabled = status.fileVaultEnabled
        isOnline = true
        consecutiveFailures = 0
        lastSeen = Date()
    }

    func markPollFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            isOnline = false
        }
    }

    func toIdentity() -> MachineIdentity {
        var identity = MachineIdentity(hardwareUUID: hardwareUUID, hostname: hostname)
        identity.displayName = displayName
        identity.thresholds = thresholds
        identity.lastKnownHostname = hostname
        identity.lastSeen = lastSeen
        identity.manualEndpoint = manualEndpoint
        return identity
    }
}
