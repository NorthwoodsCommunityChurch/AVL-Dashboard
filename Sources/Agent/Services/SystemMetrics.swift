import Foundation
import IOKit
import Shared

final class SystemMetrics {
    private let temperatureReader = TemperatureReader()
    private let cpuUsageTracker = CPUUsageTracker()
    private let networkTracker = NetworkTracker()
    private let cachedHardwareUUID: String
    private let cachedChipType: String
    private let cachedFileVault: Bool

    init() {
        cachedHardwareUUID = Self.readHardwareUUID()
        cachedChipType = Self.readChipType()
        cachedFileVault = Self.checkFileVault()
    }

    // MARK: - Full Status Snapshot

    func currentStatus() -> MachineStatus {
        MachineStatus(
            hardwareUUID: cachedHardwareUUID,
            hostname: ProcessInfo.processInfo.hostName,
            cpuTempCelsius: temperatureReader.readCPUTemperature() ?? -1,
            cpuUsagePercent: cpuUsageTracker.currentUsage(),
            networkBytesPerSec: networkTracker.currentBytesPerSec(),
            uptimeSeconds: systemUptime(),
            osVersion: osVersion(),
            chipType: cachedChipType,
            network: networkInfo(),
            fileVaultEnabled: cachedFileVault,
            agentVersion: AppVersion.current
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

    func networkInfo() -> NetworkInfo? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ipAddress: String?
        var interfaceName: String?

        // Find the first active non-loopback IPv4 interface
        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback {
                let addr = ptr.pointee.ifa_addr.pointee
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    ) == 0 {
                        let name = String(cString: ptr.pointee.ifa_name)
                        // Prefer en0 (WiFi) or en* interfaces
                        if name.hasPrefix("en") {
                            ipAddress = String(cString: hostname)
                            interfaceName = name
                            break
                        } else if ipAddress == nil {
                            ipAddress = String(cString: hostname)
                            interfaceName = name
                        }
                    }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        guard let ip = ipAddress, let ifName = interfaceName else { return nil }

        let macAddr = readMACAddress(interface: ifName)
        let ifType = interfaceType(for: ifName)

        return NetworkInfo(ipAddress: ip, macAddress: macAddr, interfaceType: ifType)
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
        switch name {
        case "en0": return "Wi-Fi"
        case "en1": return "Ethernet"
        default:
            if name.hasPrefix("en") { return "Ethernet" }
            if name.hasPrefix("bridge") { return "Bridge" }
            if name.hasPrefix("utun") { return "VPN" }
            return name
        }
    }

    // MARK: - FileVault Status (cached at launch)

    private static func checkFileVault() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("FileVault is On")
        } catch {
            return false
        }
    }
}

// MARK: - Temperature Reader (IOKit HID private API)

final class TemperatureReader {
    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>
    private typealias ClientSetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias ClientCopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServiceCopyEventFn = @convention(c) (CFTypeRef, UInt32, CFTypeRef?, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloatValueFn = @convention(c) (CFTypeRef, UInt32) -> Double
    private typealias ServiceCopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private let clientCopyServices: ClientCopyServicesFn?
    private let serviceCopyEvent: ServiceCopyEventFn?
    private let eventGetFloatValue: EventGetFloatValueFn?
    private let serviceCopyProperty: ServiceCopyPropertyFn?

    private let systemClient: CFTypeRef?

    private let kIOHIDEventTypeTemperature: UInt32 = 15

    /// Sensor name prefixes for CPU die sensors on Apple Silicon.
    private let cpuSensorPrefixes = [
        "pACC MTR Temp Sensor",  // Performance cores
        "eACC MTR Temp Sensor",  // Efficiency cores
        "PMU TP",                // Die temperature
    ]

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

        func load<T>(_ name: String) -> T? {
            guard let h = handle, let sym = dlsym(h, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }

        let create: ClientCreateFn? = load("IOHIDEventSystemClientCreate")
        let setMatching: ClientSetMatchingFn? = load("IOHIDEventSystemClientSetMatching")
        clientCopyServices = load("IOHIDEventSystemClientCopyServices")
        serviceCopyEvent = load("IOHIDServiceClientCopyEvent")
        eventGetFloatValue = load("IOHIDEventGetFloatValue")
        serviceCopyProperty = load("IOHIDServiceClientCopyProperty")

        if let create {
            systemClient = create(kCFAllocatorDefault).takeRetainedValue()
        } else {
            systemClient = nil
        }

        if let client = systemClient, let setMatching {
            let matching: [String: Int] = [
                "PrimaryUsagePage": 0xff00,
                "PrimaryUsage": 5
            ]
            setMatching(client, matching as CFDictionary)
        }
    }

    /// Reads the maximum CPU die temperature. Uses CPU-specific sensors when available,
    /// falls back to the hottest sensor if no CPU sensors are identified.
    func readCPUTemperature() -> Double? {
        guard let client = systemClient,
              let copyServices = clientCopyServices,
              let servicesRef = copyServices(client) else { return nil }

        let services = servicesRef.takeRetainedValue() as? [CFTypeRef] ?? []
        guard !services.isEmpty else { return nil }

        var cpuTemps: [Double] = []
        var allTemps: [Double] = []
        let fieldBase = kIOHIDEventTypeTemperature << 16

        for service in services {
            guard let copyEvent = serviceCopyEvent,
                  let getFloat = eventGetFloatValue,
                  let eventRef = copyEvent(service, kIOHIDEventTypeTemperature, nil, 0)
            else { continue }

            let event = eventRef.takeRetainedValue()
            let temp = getFloat(event, fieldBase)

            guard temp > 0 && temp < 150 else { continue }
            allTemps.append(temp)

            // Check if this is a CPU sensor by its Product name
            if let copyProp = serviceCopyProperty,
               let propRef = copyProp(service, "Product" as CFString) {
                let name = propRef.takeRetainedValue() as? String ?? ""
                if cpuSensorPrefixes.contains(where: { name.hasPrefix($0) }) {
                    cpuTemps.append(temp)
                }
            }
        }

        // Return max CPU temp (hottest core), or fall back to max of all sensors
        if !cpuTemps.isEmpty {
            return cpuTemps.max()
        }
        return allTemps.max()
    }
}

// MARK: - CPU Usage Tracker

final class CPUUsageTracker {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    /// Returns current CPU usage as a percentage (0–100).
    func currentUsage() -> Double {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return -1 }

        let user = UInt64(loadInfo.cpu_ticks.0)    // CPU_STATE_USER
        let system = UInt64(loadInfo.cpu_ticks.1)   // CPU_STATE_SYSTEM
        let idle = UInt64(loadInfo.cpu_ticks.2)     // CPU_STATE_IDLE
        let nice = UInt64(loadInfo.cpu_ticks.3)     // CPU_STATE_NICE

        defer {
            previousTicks = (user, system, idle, nice)
        }

        guard let prev = previousTicks else { return 0 }

        let dUser = user - prev.user
        let dSystem = system - prev.system
        let dIdle = idle - prev.idle
        let dNice = nice - prev.nice
        let total = dUser + dSystem + dIdle + dNice

        guard total > 0 else { return 0 }

        return Double(dUser + dSystem + dNice) / Double(total) * 100.0
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
