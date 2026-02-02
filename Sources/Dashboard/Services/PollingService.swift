import Foundation
import Network
import Shared

/// Polls agent endpoints for status via raw HTTP over NWConnection.
final class PollingService {
    private let queue = DispatchQueue(label: "com.computerdash.polling")

    /// Poll a single Bonjour endpoint and decode the MachineStatus response.
    func poll(endpoint: NWEndpoint, timeout: TimeInterval = 3) async throws -> MachineStatus {
        let data = try await httpGet(endpoint: endpoint, path: BonjourConstants.statusPath, timeout: timeout)

        guard let bodyData = HTTPUtils.extractBody(from: data) else {
            throw PollingError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MachineStatus.self, from: bodyData)
    }

    /// Raw HTTP GET over NWConnection to a Bonjour endpoint.
    private func httpGet(endpoint: NWEndpoint, path: String, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var completed = false

            let timeoutWork = DispatchWorkItem { [weak connection] in
                guard !completed else { return }
                completed = true
                connection?.cancel()
                continuation.resume(throwing: PollingError.timeout)
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            connection.stateUpdateHandler = { [weak connection] state in
                guard !completed else { return }
                switch state {
                case .ready:
                    let request = HTTPUtils.getRequest(path: path)
                    connection?.send(content: request, completion: .contentProcessed { error in
                        guard !completed else { return }
                        if let error {
                            completed = true
                            timeoutWork.cancel()
                            continuation.resume(throwing: error)
                            connection?.cancel()
                            return
                        }
                        // Receive until connection closes
                        self.receiveAll(connection: connection!) { result in
                            guard !completed else { return }
                            completed = true
                            timeoutWork.cancel()
                            connection?.cancel()
                            switch result {
                            case .success(let data):
                                continuation.resume(returning: data)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    })
                case .failed(let error):
                    guard !completed else { return }
                    completed = true
                    timeoutWork.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard !completed else { return }
                    completed = true
                    timeoutWork.cancel()
                    continuation.resume(throwing: PollingError.cancelled)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    /// Accumulate all data from a connection until it closes or completes.
    private func receiveAll(connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if isComplete {
                if buffer.isEmpty {
                    completion(.failure(PollingError.noData))
                } else {
                    completion(.success(buffer))
                }
            } else if let error {
                if buffer.isEmpty {
                    completion(.failure(error))
                } else {
                    // Return what we have
                    completion(.success(buffer))
                }
            } else {
                // More data to come
                self.receiveAll(connection: connection, accumulated: buffer, completion: completion)
            }
        }
    }
}

enum PollingError: Error, LocalizedError {
    case timeout
    case noData
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timeout: return "Connection timed out"
        case .noData: return "No data received"
        case .invalidResponse: return "Invalid HTTP response"
        case .cancelled: return "Connection cancelled"
        }
    }
}
