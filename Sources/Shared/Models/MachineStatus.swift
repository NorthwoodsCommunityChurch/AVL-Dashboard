import Foundation

/// JSON payload returned by each agent's /status endpoint.
public struct MachineStatus: Codable, Sendable {
    public let hardwareUUID: String
    public let hostname: String
    public let cpuTempCelsius: Double
    public let cpuUsagePercent: Double
    public let networkBytesPerSec: Double
    public let uptimeSeconds: TimeInterval
    public let osVersion: String
    public let chipType: String
    public let networks: [NetworkInfo]
    public let fileVaultEnabled: Bool
    public let agentVersion: String?
    public let gpus: [GPUStatus]?

    public init(
        hardwareUUID: String,
        hostname: String,
        cpuTempCelsius: Double,
        cpuUsagePercent: Double,
        networkBytesPerSec: Double,
        uptimeSeconds: TimeInterval,
        osVersion: String,
        chipType: String,
        networks: [NetworkInfo],
        fileVaultEnabled: Bool,
        agentVersion: String? = nil,
        gpus: [GPUStatus]? = nil
    ) {
        self.hardwareUUID = hardwareUUID
        self.hostname = hostname
        self.cpuTempCelsius = cpuTempCelsius
        self.cpuUsagePercent = cpuUsagePercent
        self.networkBytesPerSec = networkBytesPerSec
        self.uptimeSeconds = uptimeSeconds
        self.osVersion = osVersion
        self.chipType = chipType
        self.networks = networks
        self.fileVaultEnabled = fileVaultEnabled
        self.agentVersion = agentVersion
        self.gpus = gpus
    }

    // Backward-compatible decoding: accepts either "networks" array or old "network" single object.
    private enum CodingKeys: String, CodingKey {
        case hardwareUUID, hostname, cpuTempCelsius, cpuUsagePercent,
             networkBytesPerSec, uptimeSeconds, osVersion, chipType,
             networks, network, fileVaultEnabled, agentVersion, gpus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hardwareUUID = try c.decode(String.self, forKey: .hardwareUUID)
        hostname = try c.decode(String.self, forKey: .hostname)
        cpuTempCelsius = try c.decode(Double.self, forKey: .cpuTempCelsius)
        cpuUsagePercent = try c.decode(Double.self, forKey: .cpuUsagePercent)
        networkBytesPerSec = try c.decode(Double.self, forKey: .networkBytesPerSec)
        uptimeSeconds = try c.decode(TimeInterval.self, forKey: .uptimeSeconds)
        osVersion = try c.decode(String.self, forKey: .osVersion)
        chipType = try c.decode(String.self, forKey: .chipType)
        fileVaultEnabled = try c.decode(Bool.self, forKey: .fileVaultEnabled)
        agentVersion = try c.decodeIfPresent(String.self, forKey: .agentVersion)
        gpus = try c.decodeIfPresent([GPUStatus].self, forKey: .gpus)

        // Try new "networks" array first, fall back to old "network" single object
        if let arr = try? c.decode([NetworkInfo].self, forKey: .networks) {
            networks = arr
        } else if let single = try? c.decode(NetworkInfo.self, forKey: .network) {
            networks = [single]
        } else {
            networks = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hardwareUUID, forKey: .hardwareUUID)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(cpuTempCelsius, forKey: .cpuTempCelsius)
        try c.encode(cpuUsagePercent, forKey: .cpuUsagePercent)
        try c.encode(networkBytesPerSec, forKey: .networkBytesPerSec)
        try c.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(chipType, forKey: .chipType)
        try c.encode(networks, forKey: .networks)
        try c.encode(fileVaultEnabled, forKey: .fileVaultEnabled)
        try c.encodeIfPresent(agentVersion, forKey: .agentVersion)
        try c.encodeIfPresent(gpus, forKey: .gpus)
    }
}

public struct GPUStatus: Codable, Sendable, Equatable {
    public let name: String
    public let temperatureCelsius: Double
    public let usagePercent: Double

    public init(name: String, temperatureCelsius: Double, usagePercent: Double) {
        self.name = name
        self.temperatureCelsius = temperatureCelsius
        self.usagePercent = usagePercent
    }
}

public struct NetworkInfo: Codable, Sendable, Equatable {
    public let interfaceName: String
    public let ipAddress: String
    public let macAddress: String
    public let interfaceType: String

    public init(interfaceName: String, ipAddress: String, macAddress: String, interfaceType: String) {
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.interfaceType = interfaceType
    }
}
