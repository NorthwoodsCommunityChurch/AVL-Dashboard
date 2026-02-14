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
    var networks: [NetworkInfo] = []
    var fileVaultEnabled: Bool = false
    var agentVersion: String?
    var gpus: [GPUStatus] = []
    var showGPUs: Bool = false
    var isUpdating: Bool = false
    var updateError: String?
    var lastSeen: Date

    var manualEndpoint: String?
    var lastKnownIP: String?
    var isBonjourActive: Bool = false

    var isFlipped: Bool = false
    var consecutiveFailures: Int = 0
    var widgetSlots: [WidgetSlot] = WidgetSlot.defaults

    var isManual: Bool { manualEndpoint != nil }

    /// Whether this machine has reported GPU data at least once.
    var hasGPUCapability: Bool { !gpus.isEmpty }

    /// Whether the tile should render in GPU-expanded mode.
    var shouldShowGPURings: Bool { showGPUs && !gpus.isEmpty }

    /// The first/primary network interface (Ethernet preferred; used for VNC and fallback endpoint).
    var primaryNetwork: NetworkInfo? { networks.first }
    var id: String { hardwareUUID }

    init(from identity: MachineIdentity) {
        self.hardwareUUID = identity.hardwareUUID
        self.displayName = identity.displayName
        self.hostname = identity.lastKnownHostname
        self.thresholds = identity.thresholds
        self.lastSeen = identity.lastSeen
        self.manualEndpoint = identity.manualEndpoint
        self.lastKnownIP = identity.lastKnownIP
        self.widgetSlots = identity.widgetSlots ?? WidgetSlot.defaults
        self.showGPUs = identity.showGPUs ?? false
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
        networks = status.networks
        fileVaultEnabled = status.fileVaultEnabled
        agentVersion = status.agentVersion
        if let gpuData = status.gpus {
            gpus = gpuData
        }
        isOnline = true
        consecutiveFailures = 0
        lastSeen = Date()

        // Track last known IP for fallback polling when Bonjour is unavailable
        if let ip = status.networks.first?.ipAddress, !ip.isEmpty {
            lastKnownIP = ip
        }
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
        identity.lastKnownIP = lastKnownIP
        identity.widgetSlots = widgetSlots
        identity.showGPUs = showGPUs
        return identity
    }
}
