import Foundation
import Network
import Shared

/// Runs a lightweight HTTP server that responds to GET /status with system metrics.
/// Also advertises itself via Bonjour for dashboard discovery.
final class MetricsServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var dashboardConnected = false
    @Published private(set) var activePort: UInt16?

    private var listener: NWListener?
    private let systemMetrics = SystemMetrics()
    private let queue = DispatchQueue(label: "com.computerdash.agent.server")
    private var lastPollTime: Date?
    private var connectionTimer: Timer?

    init() {
        startServer()
        startConnectionMonitor()
    }

    deinit {
        connectionTimer?.invalidate()
        listener?.cancel()
    }

    // MARK: - Server Lifecycle

    private func startServer() {
        attemptListen(port: BonjourConstants.defaultPort, retriesRemaining: BonjourConstants.portRetryCount)
    }

    private func attemptListen(port: UInt16, retriesRemaining: UInt16) {
        do {
            let params = NWParameters.tcp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                startDynamicListener()
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            if retriesRemaining > 0 {
                attemptListen(port: port + 1, retriesRemaining: retriesRemaining - 1)
            } else {
                startDynamicListener()
            }
            return
        }

        configureListener()
    }

    private func startDynamicListener() {
        do {
            listener = try NWListener(using: .tcp)
            configureListener()
        } catch {
            return
        }
    }

    private func configureListener() {
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = self.listener?.port?.rawValue {
                    DispatchQueue.main.async { self.activePort = port }
                }
                self.registerBonjourService()
                DispatchQueue.main.async { self.isRunning = true }
            case .failed:
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.activePort = nil
                }
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.listener?.cancel()
                    self?.startServer()
                }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    private func registerBonjourService() {
        guard let listener else { return }
        let hostname = ProcessInfo.processInfo.hostName
        listener.service = NWListener.Service(
            name: hostname,
            type: BonjourConstants.serviceType
        )
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let requestString = String(data: data, encoding: .utf8) ?? ""

            if requestString.hasPrefix("GET \(BonjourConstants.statusPath)") {
                self.handleStatusRequest(connection: connection)
            } else {
                let response = HTTPUtils.notFoundResponse()
                connection.send(
                    content: response,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
    }

    private func handleStatusRequest(connection: NWConnection) {
        let status = systemMetrics.currentStatus()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(status) else {
            connection.cancel()
            return
        }

        let response = HTTPUtils.jsonResponse(body: jsonData)
        connection.send(
            content: response,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )

        DispatchQueue.main.async {
            self.lastPollTime = Date()
            self.dashboardConnected = true
        }
    }

    // MARK: - Dashboard Connection Tracking

    private func startConnectionMonitor() {
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let lastPoll = self.lastPollTime {
                let connected = Date().timeIntervalSince(lastPoll) < 15
                if self.dashboardConnected != connected {
                    self.dashboardConnected = connected
                }
            }
        }
    }
}
