import Foundation
import IOKit
import CoreWLAN
import Shared

final class SystemMetrics {
    private let temperatureReader = TemperatureReader()
    private let cpuUsageTracker = CPUUsageTracker()
    private let networkTracker = NetworkTracker()
    private let gpuReader = GPUMetricsReader()
    private let cachedHardwareUUID: String
    private let cachedChipType: String
    private let cachedFileVault: Bool
    private let wifiInterfaceNames: Set<String>

    init() {
        cachedHardwareUUID = Self.readHardwareUUID()
        cachedChipType = Self.readChipType()
        cachedFileVault = Self.checkFileVault()
        wifiInterfaceNames = Set(CWWiFiClient.shared().interfaceNames() ?? [])
    }

    // MARK: - Full Status Snapshot

    func currentStatus() -> MachineStatus {
        let gpuStatuses = gpuReader.currentGPUStatuses()
        return MachineStatus(
            hardwareUUID: cachedHardwareUUID,
            hostname: ProcessInfo.processInfo.hostName,
            cpuTempCelsius: temperatureReader.readCPUTemperature() ?? -1,
            cpuUsagePercent: cpuUsageTracker.currentUsage(),
            networkBytesPerSec: networkTracker.currentBytesPerSec(),
            uptimeSeconds: systemUptime(),
            osVersion: osVersion(),
            chipType: cachedChipType,
            networks: networkInterfaces(),
            fileVaultEnabled: cachedFileVault,
            agentVersion: AppVersion.current,
            gpus: gpuStatuses.isEmpty ? nil : gpuStatuses
        )
    }

    // MARK: - Hardware UUID

    static func readHardwareUUID() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return UUID().uuidString }
        defer { IOObjectRelease(service) }

        guard let uuidRef = IORegistryEntryCreateCFProperty(
            service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        ) else {
            return UUID().uuidString
        }
        return uuidRef.takeRetainedValue() as? String ?? UUID().uuidString
    }

    // MARK: - Uptime (seconds since boot)

    func systemUptime() -> TimeInterval {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boottime.tv_sec))
        return Date().timeIntervalSince(bootDate)
    }

    // MARK: - OS Version

    func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - Chip Type

    private static func readChipType() -> String {
        var size: Int = 0
        // Try Intel-style brand string first
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var result = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &result, &size, nil, 0)
            let brand = String(cString: result)
            if !brand.isEmpty { return brand }
        }
        // Fallback to hw.model for Apple Silicon
        size = 0
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var result = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &result, &size, nil, 0)
            return String(cString: result)
        }
        return "Unknown"
    }

    // MARK: - Network Info

    func networkInterfaces() -> [NetworkInfo] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [NetworkInfo] = []
        var seen = Set<String>()

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp && !isLoopback else { continue }

            let addr = current.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                current.pointee.ifa_addr, socklen_t(addr.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en"), !seen.contains(name) else { continue }

            seen.insert(name)
            let ip = String(cString: hostname)
            let mac = readMACAddress(interface: name)
            let ifType = interfaceType(for: name)

            results.append(NetworkInfo(
                interfaceName: name,
                ipAddress: ip,
                macAddress: mac,
                interfaceType: ifType
            ))
        }

        // Sort: Ethernet first (preferred for VNC), then by interface name
        return results.sorted { a, b in
            if a.interfaceType != "Wi-Fi" && b.interfaceType == "Wi-Fi" { return true }
            if a.interfaceType == "Wi-Fi" && b.interfaceType != "Wi-Fi" { return false }
            return a.interfaceName < b.interfaceName
        }
    }

    private func readMACAddress(interface: String) -> String {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, AF_LINK, NET_RT_IFLIST, 0]
        let ifIndex = if_nametoindex(interface)
        guard ifIndex > 0 else { return "Unknown" }
        mib[5] = Int32(ifIndex)

        var length: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return "Unknown"
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            return "Unknown"
        }

        let data = Data(buffer)
        let headerSize = MemoryLayout<if_msghdr>.size
        guard data.count > headerSize + 8 else { return "Unknown" }

        let sdlStart = headerSize
        let sdlNlen = Int(data[sdlStart + 5])
        let sdlAlen = Int(data[sdlStart + 6])

        guard sdlAlen == 6 else { return "Unknown" }
        let macStart = sdlStart + 8 + sdlNlen

        let bytes = data[macStart..<(macStart + 6)]
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func interfaceType(for name: String) -> String {
        if wifiInterfaceNames.contains(name) { return "Wi-Fi" }
        if name.hasPrefix("en") { return "Ethernet" }
        if name.hasPrefix("bridge") { return "Bridge" }
        if name.hasPrefix("utun") { return "VPN" }
        return name
    }

    // MARK: - FileVault Status (cached at launch)

    private static func checkFileVault() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        // Use terminationHandler + DispatchSemaphore instead of waitUntilExit().
        // waitUntilExit() spins the run loop, which allows SwiftUI to dispatch
        // view graph updates while still inside @StateObject initialization.
        // On macOS 26+, AG::precondition_failure aborts the process if the
        // SwiftUI state graph is re-entered this way.
        let sem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sem.signal() }

        do {
            try process.run()
        } catch {
            return false
        }

        _ = sem.wait(timeout: .now() + 5)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("FileVault is On")
    }
}

// MARK: - Temperature Reader (AppleSMC direct key reading)
//
// Reads CPU temperature directly from the System Management Controller.
// The previous IOKit HID approach (IOHIDEventSystemClient) returned stale cached
// data on Apple Silicon regardless of run loop scheduling. SMC key reading is the
// same mechanism used by iStat Menus, Stats.app, and other reliable monitoring tools.
//
// Key insights for Apple Silicon:
// - Service name is "AppleSMCKeysEndpoint" (vs "AppleSMC" on Intel)
// - Temperature keys use "flt " type with native (little-endian) byte order
// - CPU die temp keys are Tp** (e.g. Tp05, Tp0D) not Tc** (Intel-only)

final class TemperatureReader {
    private var connection: io_connect_t = 0

    /// Pre-discovered sensor keys with their data type and size.
    /// Populated at init by probing candidateKeys against the SMC.
    private var sensorKeys: [(keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] = []

    private let smcCmdReadKeyInfo: UInt8 = 9
    private let smcCmdReadBytes: UInt8 = 5
    private let smcCmdGetKeyFromIndex: UInt8 = 8
    private let kernelIndexSMC: UInt32 = 2

    /// Candidate CPU die temperature keys to probe at init.
    /// Apple Silicon P-core cluster keys vary by chip (M1/M2/M3/M4).
    /// Intel Tc/TC keys are included for backward compatibility.
    private static let candidateKeys: [String] = [
        // Apple Silicon P-core cluster die temperatures
        "Tp05", "Tp0D", "Tp0K", "Tp0S",
        "Tp17", "Tp1E",
        "Tp25",
        // Intel CPU die / proximity temperatures
        "Tc0c", "Tc1c", "Tc0p", "TC0P",
    ]

    /// Recognized SMC data type codes for temperature values.
    private static let knownTempTypes: Set<String> = ["flt ", "sp78", "sp87"]

    init() {
        // Apple Silicon uses AppleSMCKeysEndpoint; Intel uses AppleSMC
        var service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMCKeysEndpoint")
        )
        if service == 0 {
            service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching("AppleSMC")
            )
        }
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard connection != 0 else { return }

        // Discover which candidate keys exist on this hardware
        for keyName in Self.candidateKeys {
            let keyCode = fourCC(keyName)
            guard let (dataType, dataSize) = readKeyInfo(keyCode: keyCode),
                  dataSize > 0,
                  Self.knownTempTypes.contains(fourCCString(dataType)) else { continue }
            sensorKeys.append((keyCode: keyCode, dataType: dataType, dataSize: dataSize))
        }

        // Fallback: if no static candidates matched (e.g. M1 uses different keys),
        // enumerate all SMC keys and find temperature sensors dynamically.
        if sensorKeys.isEmpty {
            sensorKeys = discoverTemperatureKeys()
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    /// Reads CPU temperature via SMC. Returns the max across all discovered sensors.
    func readCPUTemperature() -> Double? {
        guard connection != 0, !sensorKeys.isEmpty else { return nil }

        var maxTemp = -Double.infinity
        for sensor in sensorKeys {
            if let temp = readSMCValue(
                keyCode: sensor.keyCode,
                dataType: sensor.dataType,
                dataSize: sensor.dataSize
            ), temp > 0, temp < 150 {
                maxTemp = max(maxTemp, temp)
            }
        }
        return maxTemp > 0 ? maxTemp : nil
    }

    // MARK: - SMC Communication

    /// Reads key info (data type and size) for a given SMC key code.
    private func readKeyInfo(keyCode: UInt32) -> (dataType: UInt32, dataSize: UInt32)? {
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = smcCmdReadKeyInfo

        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }
        return (output.keyInfo.dataType, output.keyInfo.dataSize)
    }

    /// Enumerates all SMC keys and returns those that look like CPU temperature sensors.
    /// Scans for keys with "Tp" or "Tc" prefix and a recognized temperature data type.
    private func discoverTemperatureKeys() -> [(keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] {
        // Read total key count from #KEY
        let hashKeyCode = fourCC("#KEY")
        guard let (_, countSize) = readKeyInfo(keyCode: hashKeyCode), countSize >= 4 else { return [] }

        var countInput = SMCKeyData()
        countInput.key = hashKeyCode
        countInput.keyInfo.dataSize = countSize
        countInput.data8 = smcCmdReadBytes

        var countOutput = SMCKeyData()
        var countOutputSize = MemoryLayout<SMCKeyData>.size

        let countResult = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &countInput, MemoryLayout<SMCKeyData>.size,
            &countOutput, &countOutputSize
        )
        guard countResult == kIOReturnSuccess else { return [] }

        var rawBytes = countOutput.bytes
        let totalKeys = withUnsafePointer(to: &rawBytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { buf in
                UInt32(buf[0]) << 24 | UInt32(buf[1]) << 16 | UInt32(buf[2]) << 8 | UInt32(buf[3])
            }
        }

        var found: [(keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] = []
        let limit = min(totalKeys, 3000)

        for i: UInt32 in 0..<limit {
            var input = SMCKeyData()
            input.data8 = smcCmdGetKeyFromIndex
            input.data32 = i

            var output = SMCKeyData()
            var outputSize = MemoryLayout<SMCKeyData>.size

            let result = IOConnectCallStructMethod(
                connection, kernelIndexSMC,
                &input, MemoryLayout<SMCKeyData>.size,
                &output, &outputSize
            )
            guard result == kIOReturnSuccess else { continue }

            let keyCode = output.key
            let firstByte = UInt8((keyCode >> 24) & 0xFF)
            let secondByte = UInt8((keyCode >> 16) & 0xFF)

            // Filter for Tp (0x54 0x70) or Tc (0x54 0x63) prefixes
            guard firstByte == 0x54, secondByte == 0x70 || secondByte == 0x63 else { continue }

            guard let (dataType, dataSize) = readKeyInfo(keyCode: keyCode),
                  dataSize > 0,
                  Self.knownTempTypes.contains(fourCCString(dataType)) else { continue }

            found.append((keyCode: keyCode, dataType: dataType, dataSize: dataSize))
        }

        return found
    }

    /// Reads the value bytes for a key and parses as a temperature.
    private func readSMCValue(keyCode: UInt32, dataType: UInt32, dataSize: UInt32) -> Double? {
        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = dataSize
        input.data8 = smcCmdReadBytes

        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }

        return parseTemperature(output: output, dataType: dataType, dataSize: dataSize)
    }

    // MARK: - Value Parsing

    private func parseTemperature(output: SMCKeyData, dataType: UInt32, dataSize: UInt32) -> Double? {
        let typeStr = fourCCString(dataType)

        var bytes = output.bytes
        return withUnsafePointer(to: &bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { buf in
                switch typeStr {
                case "flt ":
                    guard dataSize >= 4 else { return nil }
                    #if arch(arm64)
                    // Apple Silicon: SMC stores floats in native little-endian byte order
                    var value: Float = 0
                    memcpy(&value, buf, MemoryLayout<Float>.size)
                    return Double(value)
                    #else
                    // Intel: SMC stores floats in big-endian byte order
                    let raw = UInt32(buf[0]) << 24 | UInt32(buf[1]) << 16 |
                              UInt32(buf[2]) << 8  | UInt32(buf[3])
                    return Double(Float(bitPattern: raw))
                    #endif

                case "sp78":
                    // Signed 7.8 fixed-point (2 bytes, big-endian)
                    guard dataSize >= 2 else { return nil }
                    let raw = Int16(Int16(buf[0]) << 8 | Int16(buf[1]))
                    return Double(raw) / 256.0

                case "sp87":
                    // Signed 8.7 fixed-point (2 bytes, big-endian)
                    guard dataSize >= 2 else { return nil }
                    let raw = Int16(Int16(buf[0]) << 8 | Int16(buf[1]))
                    return Double(raw) / 128.0

                default:
                    return nil
                }
            }
        }
    }

    // MARK: - FourCC Helpers

    /// Encodes a 4-character string as a big-endian UInt32 SMC key code.
    private func fourCC(_ key: String) -> UInt32 {
        let c = Array(key.utf8)
        return UInt32(c[0]) << 24 | UInt32(c[1]) << 16 | UInt32(c[2]) << 8 | UInt32(c[3])
    }

    /// Decodes a UInt32 SMC key/type code back to a 4-character string.
    private func fourCCString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

// MARK: - SMC Kernel Data Structures

/// Matches the kernel's SMCKeyData_t layout for IOConnectCallStructMethod calls.
private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // C struct pads to 12 bytes (4-byte alignment); Swift only uses 9 without these.
    private var _pad1: UInt8 = 0
    private var _pad2: UInt8 = 0
    private var _pad3: UInt8 = 0
}

// MARK: - CPU Usage Tracker

final class CPUUsageTracker {
    /// Per-CPU ticks from the previous sample: [cpuIndex: (user, system, idle, nice)]
    private var previousPerCPU: [Int: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = [:]
    private let logicalCPUCount: Int

    init() {
        logicalCPUCount = ProcessInfo.processInfo.activeProcessorCount
    }

    /// Returns current CPU usage as a percentage (0–100).
    /// Uses per-CPU stats so sleeping cores on Apple Silicon count as 0% rather
    /// than being invisible (which inflates the aggregate when only E-cores are active).
    func currentUsage() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return -1 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let numCPUs = Int(cpuCount)
        var currentPerCPU: [Int: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = [:]

        var totalBusy: Double = 0
        var totalCounted: Int = 0

        for i in 0..<numCPUs {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])

            currentPerCPU[i] = (user, system, idle, nice)

            if let prev = previousPerCPU[i] {
                let dUser = user - prev.user
                let dSystem = system - prev.system
                let dIdle = idle - prev.idle
                let dNice = nice - prev.nice
                let total = dUser + dSystem + dIdle + dNice

                if total > 0 {
                    totalBusy += Double(dUser + dSystem + dNice) / Double(total)
                }
                // Cores with zero delta (sleeping) contribute 0% to totalBusy
            }
            totalCounted += 1
        }

        previousPerCPU = currentPerCPU

        // Use max of reported CPUs and known logical count to prevent inflation
        let denominator = max(totalCounted, logicalCPUCount)
        guard denominator > 0, !previousPerCPU.isEmpty else { return 0 }

        // First call has no previous data
        if totalCounted > 0 && previousPerCPU.count == numCPUs && totalBusy == 0 && previousPerCPU.count == currentPerCPU.count {
            // Check if this is truly the first measurement
            let hasPrevious = previousPerCPU.values.contains { $0.user > 0 || $0.system > 0 || $0.idle > 0 }
            if !hasPrevious { return 0 }
        }

        return (totalBusy / Double(denominator)) * 100.0
    }
}

// MARK: - Network Traffic Tracker

final class NetworkTracker {
    private var previousBytes: UInt64 = 0
    private var previousTime: Date?

    /// Returns combined in+out bytes per second across all active interfaces.
    func currentBytesPerSec() -> Double {
        let totalBytes = readTotalBytes()
        let now = Date()

        defer {
            previousBytes = totalBytes
            previousTime = now
        }

        guard let prevTime = previousTime, previousBytes > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0 else { return 0 }

        let delta = totalBytes > previousBytes ? totalBytes - previousBytes : 0
        return Double(delta) / elapsed
    }

    private func readTotalBytes() -> UInt64 {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return 0 }
        defer { freeifaddrs(ifaddr) }

        var total: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            // Only count active non-loopback link-layer entries
            if isUp && !isLoopback && current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) && name.hasPrefix("en") {
                if let data = current.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    total += UInt64(networkData.ifi_ibytes)
                    total += UInt64(networkData.ifi_obytes)
                }
            }

            ptr = current.pointee.ifa_next
        }

        return total
    }
}

// MARK: - GPU Metrics Reader (AMD discrete GPUs)
//
// Reads GPU temperature from SMC keys (TG0D, TG1D, TG2D for AMD GPUs in Mac Pro)
// and GPU utilization from IOAccelerator PerformanceStatistics.

final class GPUMetricsReader {
    private var connection: io_connect_t = 0

    /// Discovered GPU temperature keys, ordered by GPU index.
    private var gpuTempKeys: [(index: Int, keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] = []

    /// GPU names from IOAccelerator, keyed by index.
    private var gpuNames: [Int: String] = [:]

    private let smcCmdReadKeyInfo: UInt8 = 9
    private let smcCmdReadBytes: UInt8 = 5
    private let smcCmdGetKeyFromIndex: UInt8 = 8
    private let kernelIndexSMC: UInt32 = 2

    /// Recognized SMC data type codes for temperature values.
    private static let knownTempTypes: Set<String> = ["flt ", "sp78", "sp87"]

    /// Candidate GPU die temperature keys. TG{n}D = GPU n die temperature.
    private static let candidateKeys: [(index: Int, name: String)] = [
        (0, "TG0D"), (1, "TG1D"), (2, "TG2D"), (3, "TG3D"),
        // Alternative keys used by some AMD GPUs
        (0, "TG0T"), (1, "TG1T"), (2, "TG2T"), (3, "TG3T"),
    ]

    init() {
        // Open SMC connection (same pattern as TemperatureReader)
        var service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMCKeysEndpoint")
        )
        if service == 0 {
            service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching("AppleSMC")
            )
        }
        if service != 0 {
            defer { IOObjectRelease(service) }
            IOServiceOpen(service, mach_task_self_, 0, &connection)
        }

        // Discover GPU names first so we know how many GPUs to expect
        discoverGPUNames()
        let gpuCount = max(gpuNames.count, 1)

        if connection != 0 {
            // Try static candidate keys first
            var seenIndices = Set<Int>()
            for candidate in Self.candidateKeys {
                guard !seenIndices.contains(candidate.index) else { continue }
                let keyCode = fourCC(candidate.name)
                guard let (dataType, dataSize) = readKeyInfo(keyCode: keyCode),
                      dataSize > 0,
                      Self.knownTempTypes.contains(fourCCString(dataType)) else { continue }
                gpuTempKeys.append((index: candidate.index, keyCode: keyCode, dataType: dataType, dataSize: dataSize))
                seenIndices.insert(candidate.index)
            }

            // Fallback: if static keys didn't find temps for all GPUs,
            // enumerate all SMC keys with "TG" prefix dynamically.
            if gpuTempKeys.count < gpuCount {
                gpuTempKeys = discoverGPUTemperatureKeys()
            }
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    /// Returns current GPU statuses (temperature + utilization) for all detected GPUs.
    func currentGPUStatuses() -> [GPUStatus] {
        let temps = readGPUTemperatures()
        let usage = readGPUUtilization()

        let maxIndex = max(
            temps.keys.max() ?? -1,
            usage.keys.max() ?? -1,
            gpuNames.keys.max() ?? -1
        )
        guard maxIndex >= 0 else { return [] }

        var statuses: [GPUStatus] = []
        for i in 0...maxIndex {
            let name = gpuNames[i] ?? "GPU \(i)"
            let temp = temps[i] ?? -1
            let util = usage[i] ?? -1
            statuses.append(GPUStatus(name: name, temperatureCelsius: temp, usagePercent: util))
        }
        return statuses
    }

    // MARK: - GPU Temperature via SMC

    private func readGPUTemperatures() -> [Int: Double] {
        guard connection != 0 else { return [:] }
        var result: [Int: Double] = [:]
        for sensor in gpuTempKeys {
            if let temp = readSMCValue(keyCode: sensor.keyCode, dataType: sensor.dataType, dataSize: sensor.dataSize),
               temp > 0, temp < 150 {
                result[sensor.index] = temp
            }
        }
        return result
    }

    /// Enumerates all SMC keys and returns those that look like GPU temperature sensors.
    /// Groups by GPU index (3rd character digit) and picks one "best" key per GPU,
    /// preferring die temperature keys (4th char 'D' or 'd').
    private func discoverGPUTemperatureKeys() -> [(index: Int, keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] {
        // Read total key count from #KEY
        let hashKeyCode = fourCC("#KEY")
        guard let (_, countSize) = readKeyInfo(keyCode: hashKeyCode), countSize >= 4 else { return [] }

        var countInput = SMCKeyData()
        countInput.key = hashKeyCode
        countInput.keyInfo.dataSize = countSize
        countInput.data8 = smcCmdReadBytes

        var countOutput = SMCKeyData()
        var countOutputSize = MemoryLayout<SMCKeyData>.size

        let countResult = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &countInput, MemoryLayout<SMCKeyData>.size,
            &countOutput, &countOutputSize
        )
        guard countResult == kIOReturnSuccess else { return [] }

        var rawBytes = countOutput.bytes
        let totalKeys = withUnsafePointer(to: &rawBytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { buf in
                UInt32(buf[0]) << 24 | UInt32(buf[1]) << 16 | UInt32(buf[2]) << 8 | UInt32(buf[3])
            }
        }

        // Collect all TG** keys that are valid temperature sensors
        // Key format: T(0x54) G(0x47) <index-char> <type-char>
        var allGPUKeys: [(keyCode: UInt32, dataType: UInt32, dataSize: UInt32, indexChar: UInt8, typeChar: UInt8)] = []
        let limit = min(totalKeys, 3000)

        for i: UInt32 in 0..<limit {
            var input = SMCKeyData()
            input.data8 = smcCmdGetKeyFromIndex
            input.data32 = i

            var output = SMCKeyData()
            var outputSize = MemoryLayout<SMCKeyData>.size

            let result = IOConnectCallStructMethod(
                connection, kernelIndexSMC,
                &input, MemoryLayout<SMCKeyData>.size,
                &output, &outputSize
            )
            guard result == kIOReturnSuccess else { continue }

            let keyCode = output.key
            let byte1 = UInt8((keyCode >> 24) & 0xFF)  // 'T'
            let byte2 = UInt8((keyCode >> 16) & 0xFF)  // 'G'
            let byte3 = UInt8((keyCode >> 8) & 0xFF)   // index char
            let byte4 = UInt8(keyCode & 0xFF)           // type char

            // Filter for TG prefix (0x54 0x47)
            guard byte1 == 0x54, byte2 == 0x47 else { continue }

            guard let (dataType, dataSize) = readKeyInfo(keyCode: keyCode),
                  dataSize > 0,
                  Self.knownTempTypes.contains(fourCCString(dataType)) else { continue }

            allGPUKeys.append((keyCode: keyCode, dataType: dataType, dataSize: dataSize, indexChar: byte3, typeChar: byte4))
        }

        // Group keys by the index character (3rd byte) and pick best per group.
        // Prefer die temp keys: 'D', 'd', then anything else.
        var groups: [UInt8: [(keyCode: UInt32, dataType: UInt32, dataSize: UInt32, typeChar: UInt8)]] = [:]
        for key in allGPUKeys {
            groups[key.indexChar, default: []].append((key.keyCode, key.dataType, key.dataSize, key.typeChar))
        }

        var result: [(index: Int, keyCode: UInt32, dataType: UInt32, dataSize: UInt32)] = []
        for (_, keys) in groups.sorted(by: { $0.key < $1.key }) {
            // Pick the best key: prefer 'D'/'d' (die), then 'T'/'t', then first available
            let best = keys.first(where: { $0.typeChar == 0x44 || $0.typeChar == 0x64 })  // 'D' or 'd'
                     ?? keys.first(where: { $0.typeChar == 0x54 || $0.typeChar == 0x74 })  // 'T' or 't'
                     ?? keys.first
            if let best {
                result.append((index: result.count, keyCode: best.keyCode, dataType: best.dataType, dataSize: best.dataSize))
            }
        }

        return result
    }

    // MARK: - GPU Utilization via IOAccelerator

    private func readGPUUtilization() -> [Int: Double] {
        var result: [Int: Double] = [:]

        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return result }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var gpuIndex = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perfStats = dict["PerformanceStatistics"] as? [String: Any] else {
                gpuIndex += 1
                continue
            }

            // Different AMD drivers use different key names
            if let val = perfStats["Device Utilization %"] as? NSNumber {
                result[gpuIndex] = val.doubleValue
            } else if let val = perfStats["GPU Activity(%)"] as? NSNumber {
                result[gpuIndex] = val.doubleValue
            }

            gpuIndex += 1
        }

        return result
    }

    /// Discover GPU names from IOAccelerator IORegistry entries.
    private func discoverGPUNames() {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var gpuIndex = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            // Walk up to parent IOPCIDevice to get the model name
            var parent: io_object_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == kIOReturnSuccess {
                defer { IOObjectRelease(parent) }
                if let modelProp = IORegistryEntryCreateCFProperty(parent, "model" as CFString, kCFAllocatorDefault, 0) {
                    if let modelData = modelProp.takeRetainedValue() as? Data {
                        let name = String(data: modelData, encoding: .utf8)?
                            .trimmingCharacters(in: .controlCharacters) ?? "GPU \(gpuIndex)"
                        gpuNames[gpuIndex] = name
                    }
                }
            }

            gpuIndex += 1
        }
    }

    // MARK: - SMC Communication (same pattern as TemperatureReader)

    private func readKeyInfo(keyCode: UInt32) -> (dataType: UInt32, dataSize: UInt32)? {
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = smcCmdReadKeyInfo

        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }
        return (output.keyInfo.dataType, output.keyInfo.dataSize)
    }

    private func readSMCValue(keyCode: UInt32, dataType: UInt32, dataSize: UInt32) -> Double? {
        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = dataSize
        input.data8 = smcCmdReadBytes

        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = IOConnectCallStructMethod(
            connection, kernelIndexSMC,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }

        return parseTemperature(output: output, dataType: dataType, dataSize: dataSize)
    }

    private func parseTemperature(output: SMCKeyData, dataType: UInt32, dataSize: UInt32) -> Double? {
        let typeStr = fourCCString(dataType)

        var bytes = output.bytes
        return withUnsafePointer(to: &bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 32) { buf in
                switch typeStr {
                case "flt ":
                    guard dataSize >= 4 else { return nil }
                    #if arch(arm64)
                    var value: Float = 0
                    memcpy(&value, buf, MemoryLayout<Float>.size)
                    return Double(value)
                    #else
                    let raw = UInt32(buf[0]) << 24 | UInt32(buf[1]) << 16 |
                              UInt32(buf[2]) << 8  | UInt32(buf[3])
                    return Double(Float(bitPattern: raw))
                    #endif

                case "sp78":
                    guard dataSize >= 2 else { return nil }
                    let raw = Int16(Int16(buf[0]) << 8 | Int16(buf[1]))
                    return Double(raw) / 256.0

                case "sp87":
                    guard dataSize >= 2 else { return nil }
                    let raw = Int16(Int16(buf[0]) << 8 | Int16(buf[1]))
                    return Double(raw) / 128.0

                default:
                    return nil
                }
            }
        }
    }

    private func fourCC(_ key: String) -> UInt32 {
        let c = Array(key.utf8)
        return UInt32(c[0]) << 24 | UInt32(c[1]) << 16 | UInt32(c[2]) << 8 | UInt32(c[3])
    }

    private func fourCCString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
