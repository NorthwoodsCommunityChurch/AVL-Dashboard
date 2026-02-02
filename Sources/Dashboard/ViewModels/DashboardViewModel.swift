import Foundation
import Network
import Observation
import Shared

@Observable
final class DashboardViewModel {
    var machines: [MachineViewModel] = []
    var sortOrder: MachineSortOrder = .name {
        didSet { persist() }
    }

    /// Whether the Dashboard app itself has an update available.
    var dashboardUpdateAvailable: Bool = false
    /// Whether we're currently checking GitHub for updates.
    var isCheckingForUpdates: Bool = false
    /// The latest version string from GitHub (for display).
    var latestVersionString: String?
    /// Whether we're currently downloading and applying a dashboard self-update.
    var isDownloadingDashboardUpdate: Bool = false
    /// Error message if dashboard self-update failed.
    var dashboardUpdateError: String?

    var sortedMachines: [MachineViewModel] {
        switch sortOrder {
        case .name:
            machines.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .temperature:
            machines.sorted { $0.cpuTemp > $1.cpuTemp }
        case .uptime:
            machines.sorted { $0.uptimeSeconds > $1.uptimeSeconds }
        }
    }

    private let discovery = DiscoveryService()
    private let polling = PollingService()
    private let persistence = PersistenceService()
    let updateService = UpdateService()

    /// Map of Bonjour service names to their endpoints for active polling.
    private var activeEndpoints: [String: NWEndpoint] = [:]
    /// Map of Bonjour service names to known hardwareUUID (set after first successful poll).
    private var serviceToUUID: [String: String] = [:]
    /// Active polling tasks keyed by service name.
    private var pollingTasks: [String: Task<Void, Never>] = [:]

    /// Active manual polling tasks keyed by endpoint string ("host:port").
    private var manualPollingTasks: [String: Task<Void, Never>] = [:]
    /// Map of manual endpoint strings to known hardwareUUID.
    private var manualEndpointToUUID: [String: String] = [:]

    private var updateCheckTask: Task<Void, Never>?

    init() {
        loadPersistedData()
        setupDiscovery()
        discovery.startBrowsing()
        startManualEndpointPolling()
        startUpdateChecking()
    }

    // MARK: - Persistence

    private func loadPersistedData() {
        let stored = persistence.load()
        sortOrder = stored.sortOrder
        machines = stored.machines.map { MachineViewModel(from: $0) }
    }

    func persist() {
        let identities = machines.map { $0.toIdentity() }
        persistence.saveMachines(identities, sortOrder: sortOrder)
    }

    func saveMachine(_ machine: MachineViewModel) {
        persist()
    }

    func deleteMachine(id: String) {
        if let machine = machines.first(where: { $0.hardwareUUID == id }),
           let endpoint = machine.manualEndpoint {
            manualPollingTasks[endpoint]?.cancel()
            manualPollingTasks.removeValue(forKey: endpoint)
            manualEndpointToUUID.removeValue(forKey: endpoint)
        }
        machines.removeAll { $0.hardwareUUID == id }
        serviceToUUID = serviceToUUID.filter { $0.value != id }
        persist()
    }

    // MARK: - Discovery

    private func setupDiscovery() {
        discovery.onEndpointFound = { [weak self] endpoint, serviceName in
            DispatchQueue.main.async {
                self?.handleEndpointFound(endpoint: endpoint, serviceName: serviceName)
            }
        }

        discovery.onEndpointLost = { [weak self] serviceName in
            DispatchQueue.main.async {
                self?.handleEndpointLost(serviceName: serviceName)
            }
        }
    }

    private func handleEndpointFound(endpoint: NWEndpoint, serviceName: String) {
        activeEndpoints[serviceName] = endpoint
        startPolling(serviceName: serviceName, endpoint: endpoint)
    }

    private func handleEndpointLost(serviceName: String) {
        activeEndpoints.removeValue(forKey: serviceName)
        pollingTasks[serviceName]?.cancel()
        pollingTasks.removeValue(forKey: serviceName)

        if let uuid = serviceToUUID[serviceName],
           let machine = machines.first(where: { $0.hardwareUUID == uuid }) {
            machine.isBonjourActive = false
        }
    }

    // MARK: - Bonjour Polling

    private func startPolling(serviceName: String, endpoint: NWEndpoint) {
        pollingTasks[serviceName]?.cancel()

        pollingTasks[serviceName] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce(serviceName: serviceName, endpoint: endpoint)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func pollOnce(serviceName: String, endpoint: NWEndpoint) async {
        do {
            let status = try await polling.poll(endpoint: endpoint)
            await MainActor.run {
                self.handlePollSuccess(serviceName: serviceName, status: status)
            }
        } catch {
            await MainActor.run {
                self.handlePollFailure(serviceName: serviceName)
            }
        }
    }

    private func handlePollSuccess(serviceName: String, status: MachineStatus) {
        serviceToUUID[serviceName] = status.hardwareUUID

        if let existing = machines.first(where: { $0.hardwareUUID == status.hardwareUUID }) {
            existing.update(from: status)
            existing.isBonjourActive = true
        } else {
            let machine = MachineViewModel(from: status)
            machine.isBonjourActive = true
            machines.append(machine)
        }

        persist()
    }

    private func handlePollFailure(serviceName: String) {
        guard let uuid = serviceToUUID[serviceName],
              let machine = machines.first(where: { $0.hardwareUUID == uuid }) else { return }
        machine.markPollFailure()
    }

    // MARK: - Manual Endpoint Polling

    private func startManualEndpointPolling() {
        for machine in machines where machine.manualEndpoint != nil {
            startManualPolling(endpointString: machine.manualEndpoint!)
        }
    }

    func addManualEndpoint(host: String, port: UInt16) {
        let portToUse = port > 0 ? port : BonjourConstants.defaultPort
        let endpointString = "\(host):\(portToUse)"

        guard !machines.contains(where: { $0.manualEndpoint == endpointString }),
              !manualPollingTasks.keys.contains(endpointString) else { return }

        startManualPolling(endpointString: endpointString)
    }

    private func startManualPolling(endpointString: String) {
        guard let (host, port) = parseEndpoint(endpointString) else { return }

        manualPollingTasks[endpointString]?.cancel()

        let nwEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: BonjourConstants.defaultPort)!
        )

        manualPollingTasks[endpointString] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollManualOnce(endpointString: endpointString, endpoint: nwEndpoint)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func pollManualOnce(endpointString: String, endpoint: NWEndpoint) async {
        do {
            let status = try await polling.poll(endpoint: endpoint)
            await MainActor.run {
                self.handleManualPollSuccess(endpointString: endpointString, status: status)
            }
        } catch {
            await MainActor.run {
                self.handleManualPollFailure(endpointString: endpointString)
            }
        }
    }

    private func handleManualPollSuccess(endpointString: String, status: MachineStatus) {
        manualEndpointToUUID[endpointString] = status.hardwareUUID

        if let existing = machines.first(where: { $0.hardwareUUID == status.hardwareUUID }) {
            if existing.manualEndpoint == nil {
                existing.manualEndpoint = endpointString
            }
            if !existing.isBonjourActive {
                existing.update(from: status)
            }
        } else {
            let machine = MachineViewModel(from: status)
            machine.manualEndpoint = endpointString
            machines.append(machine)
        }

        persist()
    }

    private func handleManualPollFailure(endpointString: String) {
        guard let uuid = manualEndpointToUUID[endpointString],
              let machine = machines.first(where: { $0.hardwareUUID == uuid }) else { return }
        if !machine.isBonjourActive {
            machine.markPollFailure()
        }
    }

    private func parseEndpoint(_ endpointString: String) -> (String, UInt16)? {
        let parts = endpointString.split(separator: ":", maxSplits: 1)
        let host = String(parts[0])
        let port: UInt16
        if parts.count > 1, let p = UInt16(parts[1]) {
            port = p
        } else {
            port = BonjourConstants.defaultPort
        }
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    // MARK: - Update Checking

    private func startUpdateChecking() {
        updateCheckTask = Task { [weak self] in
            // Check on launch
            await self?.checkForUpdates()

            // Then every 15 minutes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await self?.checkForUpdates()
            }
        }
    }

    func checkForUpdates() async {
        await MainActor.run { self.isCheckingForUpdates = true }

        await updateService.checkForUpdate()

        await MainActor.run {
            self.isCheckingForUpdates = false
            self.dashboardUpdateAvailable = self.updateService.updateAvailable
            self.latestVersionString = self.updateService.latestVersion?.description
        }
    }

    /// Manual check triggered by toolbar button — bypasses cache.
    func forceCheckForUpdates() async {
        await MainActor.run { self.isCheckingForUpdates = true }

        await updateService.forceCheck()

        await MainActor.run {
            self.isCheckingForUpdates = false
            self.dashboardUpdateAvailable = self.updateService.updateAvailable
            self.latestVersionString = self.updateService.latestVersion?.description
        }
    }

    /// Download and apply a self-update to the Dashboard app.
    func updateDashboard() async {
        await MainActor.run {
            self.isDownloadingDashboardUpdate = true
            self.dashboardUpdateError = nil
        }

        do {
            let zipData = try await updateService.downloadDashboardUpdate()
            try DashboardUpdateManager.shared.applyUpdate(zipData: zipData)
            // If we reach here, the app is about to terminate and relaunch
        } catch {
            await MainActor.run {
                self.isDownloadingDashboardUpdate = false
                self.dashboardUpdateError = error.localizedDescription
            }
        }
    }

    /// Whether a specific machine's agent needs updating.
    /// Only returns true when the dashboard itself is up to date.
    func machineNeedsUpdate(_ machine: MachineViewModel) -> Bool {
        guard !dashboardUpdateAvailable else { return false }
        return updateService.agentNeedsUpdate(version: machine.agentVersion)
    }

    /// Push an update to a specific agent. Uses the machine's known endpoint.
    func pushUpdate(to machine: MachineViewModel) async {
        guard let endpoint = resolveEndpoint(for: machine) else { return }

        await MainActor.run { machine.isUpdating = true; machine.updateError = nil }

        do {
            try await updateService.pushUpdateToAgent(endpoint: endpoint)
            await MainActor.run { machine.isUpdating = false }
        } catch {
            await MainActor.run {
                machine.isUpdating = false
                machine.updateError = error.localizedDescription
            }
        }
    }

    /// Resolve an NWEndpoint for a machine (prefers manual endpoint, then Bonjour).
    private func resolveEndpoint(for machine: MachineViewModel) -> NWEndpoint? {
        if let manual = machine.manualEndpoint, let (host, port) = parseEndpoint(manual) {
            return NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: BonjourConstants.defaultPort)!
            )
        }

        // Try Bonjour endpoint
        if let serviceName = serviceToUUID.first(where: { $0.value == machine.hardwareUUID })?.key {
            return activeEndpoints[serviceName]
        }

        // Last resort: use networkInfo IP
        if let ip = machine.networkInfo?.ipAddress {
            return NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: BonjourConstants.defaultPort)!
            )
        }

        return nil
    }
}
