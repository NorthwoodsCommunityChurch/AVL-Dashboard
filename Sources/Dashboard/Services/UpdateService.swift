import Foundation
import Network
import Shared

/// Checks GitHub for new releases and triggers Sparkle updates on agents.
final class UpdateService: @unchecked Sendable {
    private let owner = "NorthwoodsCommunityChurch"
    private let repo = "AVL-Dashboard"

    private(set) var latestRelease: GitHubRelease?
    private(set) var latestVersion: SemanticVersion?
    private var lastCheck: Date?

    /// The current app version parsed as a SemanticVersion.
    var currentVersion: SemanticVersion? {
        SemanticVersion(AppVersion.current)
    }

    /// Whether a newer version is available on GitHub.
    var updateAvailable: Bool {
        guard let latest = latestVersion, let current = currentVersion else { return false }
        return latest > current
    }

    /// Check GitHub for the latest release. Caches for 15 minutes.
    func checkForUpdate() async {
        if let last = lastCheck, Date().timeIntervalSince(last) < 900 {
            return
        }

        do {
            let releases = try await fetchReleases()
            // Find the newest release by semantic version
            let best = releases
                .compactMap { release -> (GitHubRelease, SemanticVersion)? in
                    guard let v = SemanticVersion(release.tagName) else { return nil }
                    return (release, v)
                }
                .sorted { $0.1 > $1.1 }
                .first

            latestRelease = best?.0
            latestVersion = best?.1
            lastCheck = Date()
        } catch {
            // Silently fail — network may be unavailable
        }
    }

    /// Force a fresh check ignoring cache.
    func forceCheck() async {
        lastCheck = nil
        await checkForUpdate()
    }

    /// Whether a specific agent version is outdated compared to the latest GitHub release.
    func agentNeedsUpdate(version: String?) -> Bool {
        guard let latest = latestVersion else { return false }
        guard let versionStr = version, let agentVer = SemanticVersion(versionStr) else {
            return false // Unknown version — don't push update
        }
        return latest > agentVer
    }

    /// Trigger Sparkle update check on an agent by POSTing to /update endpoint.
    func pushUpdateToAgent(endpoint: NWEndpoint, agentVersion: String?) async throws {
        try await triggerSparkleUpdate(endpoint: endpoint)
    }

    // MARK: - GitHub API

    private func fetchReleases() async throws -> [GitHubRelease] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.githubAPIError
        }

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    // MARK: - Trigger Agent Update

    /// Send a simple POST to /update to trigger Sparkle on the agent.
    private func triggerSparkleUpdate(endpoint: NWEndpoint) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.computerdash.update.trigger")
            var completed = false

            let timeoutWork = DispatchWorkItem { [weak connection] in
                guard !completed else { return }
                completed = true
                connection?.cancel()
                continuation.resume(throwing: UpdateError.timeout)
            }
            queue.asyncAfter(deadline: .now() + 10, execute: timeoutWork)

            connection.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready:
                    // Simple POST with empty body to trigger Sparkle
                    let request = "POST \(BonjourConstants.updatePath) HTTP/1.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
                        guard !completed else { return }
                        if let error {
                            completed = true
                            timeoutWork.cancel()
                            connection.cancel()
                            continuation.resume(throwing: error)
                            return
                        }

                        // Read response
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { responseData, _, _, recvError in
                            guard !completed else { return }
                            completed = true
                            timeoutWork.cancel()
                            connection.cancel()

                            if let recvError {
                                continuation.resume(throwing: recvError)
                                return
                            }

                            // Check for HTTP 200
                            if let responseData,
                               let responseStr = String(data: responseData, encoding: .utf8),
                               responseStr.contains("200") {
                                continuation.resume()
                            } else {
                                let detail: String
                                if let responseData,
                                   let responseStr = String(data: responseData, encoding: .utf8) {
                                    detail = responseStr.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
                                } else {
                                    detail = "No response from agent"
                                }
                                continuation.resume(throwing: UpdateError.agentRejected(detail: detail))
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
                    continuation.resume(throwing: UpdateError.cancelled)
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}

enum UpdateError: Error, LocalizedError {
    case githubAPIError
    case timeout
    case cancelled
    case agentRejected(detail: String)

    var errorDescription: String? {
        switch self {
        case .githubAPIError: return "GitHub API request failed"
        case .timeout: return "Update request timed out"
        case .cancelled: return "Update cancelled"
        case .agentRejected(let detail): return "Agent rejected: \(detail)"
        }
    }
}
