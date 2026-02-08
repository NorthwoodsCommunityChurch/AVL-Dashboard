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
    private var isUpdating = false

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

            let method = HTTPUtils.parseMethod(from: data)
            let path = HTTPUtils.parsePath(from: data)

            if method == "GET" && path == BonjourConstants.statusPath {
                self.handleStatusRequest(connection: connection)
            } else if method == "POST" && path == BonjourConstants.updatePath {
                self.handleUpdateRequest(connection: connection, initialData: data)
            } else if method == "POST" && path == BonjourConstants.checkUpdatesPath {
                self.handleCheckUpdatesRequest(connection: connection)
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

    // MARK: - Software Update Check

    private func handleCheckUpdatesRequest(connection: NWConnection) {
        Task {
            await systemMetrics.forceUpdateCheck()
            let status = systemMetrics.currentStatus()

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let jsonData = try? encoder.encode(status) else {
                let response = HTTPUtils.errorResponse(status: 500, message: "Failed to encode response")
                connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                              completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            let response = HTTPUtils.jsonResponse(body: jsonData)
            connection.send(
                content: response,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }

    // MARK: - Update Handling

    private func handleUpdateRequest(connection: NWConnection, initialData: Data) {
        guard !isUpdating else {
            let response = HTTPUtils.errorResponse(status: 409, message: "Update already in progress")
            connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        isUpdating = true

        guard let contentLength = HTTPUtils.parseContentLength(from: initialData) else {
            isUpdating = false
            let response = HTTPUtils.errorResponse(status: 400, message: "Missing Content-Length")
            connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        let maxSize = 50 * 1024 * 1024
        guard contentLength <= maxSize else {
            isUpdating = false
            let response = HTTPUtils.errorResponse(status: 413, message: "Payload too large (50MB max)")
            connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        // Extract any body bytes already received in the initial chunk
        let initialBody: Data
        if let body = HTTPUtils.extractBody(from: initialData) {
            initialBody = body
        } else {
            initialBody = Data()
        }

        if initialBody.count >= contentLength {
            // All data arrived in the first chunk
            let zipData = initialBody.prefix(contentLength)
            self.processUpdateData(Data(zipData), connection: connection)
        } else {
            // Need to accumulate more data
            self.receiveUpdateBody(
                connection: connection,
                accumulated: initialBody,
                expected: contentLength
            )
        }
    }

    private func receiveUpdateBody(connection: NWConnection, accumulated: Data, expected: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.count >= expected || isComplete {
                let zipData = buffer.prefix(expected)
                self.processUpdateData(Data(zipData), connection: connection)
            } else if error != nil {
                self.isUpdating = false
                let response = HTTPUtils.errorResponse(status: 500, message: "Transfer failed")
                connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                              completion: .contentProcessed { _ in connection.cancel() })
            } else {
                self.receiveUpdateBody(connection: connection, accumulated: buffer, expected: expected)
            }
        }
    }

    private func processUpdateData(_ zipData: Data, connection: NWConnection) {
        do {
            // Send 200 OK before starting the update (agent will terminate soon)
            let response = HTTPUtils.okResponse(message: "Update accepted")
            connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { [weak self] _ in
                connection.cancel()
                // Apply update on main queue after response is sent
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        try UpdateManager.shared.applyUpdate(zipData: zipData)
                    } catch {
                        self?.isUpdating = false
                    }
                }
            })
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
