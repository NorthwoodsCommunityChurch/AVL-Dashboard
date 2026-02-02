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
    public let network: NetworkInfo?
    public let fileVaultEnabled: Bool

    public init(
        hardwareUUID: String,
        hostname: String,
        cpuTempCelsius: Double,
        cpuUsagePercent: Double,
        networkBytesPerSec: Double,
        uptimeSeconds: TimeInterval,
        osVersion: String,
        chipType: String,
        network: NetworkInfo?,
        fileVaultEnabled: Bool
    ) {
        self.hardwareUUID = hardwareUUID
        self.hostname = hostname
        self.cpuTempCelsius = cpuTempCelsius
        self.cpuUsagePercent = cpuUsagePercent
        self.networkBytesPerSec = networkBytesPerSec
        self.uptimeSeconds = uptimeSeconds
        self.osVersion = osVersion
        self.chipType = chipType
        self.network = network
        self.fileVaultEnabled = fileVaultEnabled
    }
}

public struct NetworkInfo: Codable, Sendable, Equatable {
    public let ipAddress: String
    public let macAddress: String
    public let interfaceType: String

    public init(ipAddress: String, macAddress: String, interfaceType: String) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.interfaceType = interfaceType
    }
}
