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

    init() {
        loadPersistedData()
        setupDiscovery()
        discovery.startBrowsing()
        startManualEndpointPolling()
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
}
