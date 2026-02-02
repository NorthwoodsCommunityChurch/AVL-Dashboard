import Foundation
import Network
import Shared

/// Checks GitHub for new releases and manages pushing updates to agents.
final class UpdateService: @unchecked Sendable {
    private let owner = "NorthwoodsCommunityChurch"
    private let repo = "AVL-Dashboard"
    private let polling = PollingService()

    private(set) var latestRelease: GitHubRelease?
    private(set) var latestVersion: SemanticVersion?
    private var cachedAgentZipData: Data?
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
            cachedAgentZipData = nil // invalidate cached zip on new check
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

    /// Download the agent zip from GitHub and POST it to an agent endpoint.
    func pushUpdateToAgent(endpoint: NWEndpoint) async throws {
        guard let release = latestRelease else {
            throw UpdateError.noReleaseAvailable
        }

        let agentAsset = release.assets.first { $0.name.lowercased().contains("agent") && $0.name.hasSuffix(".zip") }
        guard let asset = agentAsset else {
            throw UpdateError.noAgentAssetFound
        }

        let zipData: Data
        if let cached = cachedAgentZipData {
            zipData = cached
        } else {
            zipData = try await downloadAsset(url: asset.browserDownloadUrl)
            cachedAgentZipData = zipData
        }

        try await postUpdate(endpoint: endpoint, data: zipData)
    }

    /// Download the Dashboard zip from the latest GitHub release.
    func downloadDashboardUpdate() async throws -> Data {
        guard let release = latestRelease else {
            throw UpdateError.noReleaseAvailable
        }

        let dashAsset = release.assets.first {
            !$0.name.lowercased().contains("agent") && $0.name.hasSuffix(".zip")
        }
        guard let asset = dashAsset else {
            throw UpdateError.noDashboardAssetFound
        }

        return try await downloadAsset(url: asset.browserDownloadUrl)
    }

    /// Download the agent zip from GitHub and POST it to a host:port endpoint.
    func pushUpdateToAgent(host: String, port: UInt16) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: BonjourConstants.defaultPort)!
        )
        try await pushUpdateToAgent(endpoint: endpoint)
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

    private func downloadAsset(url: String) async throws -> Data {
        guard let assetURL = URL(string: url) else {
            throw UpdateError.invalidAssetURL
        }

        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        return data
    }

    // MARK: - Push Update to Agent

    private func postUpdate(endpoint: NWEndpoint, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.computerdash.update.post")
            var completed = false

            let timeoutWork = DispatchWorkItem { [weak connection] in
                guard !completed else { return }
                completed = true
                connection?.cancel()
                continuation.resume(throwing: UpdateError.timeout)
            }
            queue.asyncAfter(deadline: .now() + 30, execute: timeoutWork)

            connection.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready:
                    let request = HTTPUtils.postRequest(
                        path: BonjourConstants.updatePath,
                        body: data,
                        contentType: "application/zip"
                    )
                    connection.send(content: request, completion: .contentProcessed { error in
                        guard !completed else { return }
                        if let error {
                            completed = true
                            timeoutWork.cancel()
                            connection.cancel()
                            continuation.resume(throwing: error)
                            return
                        }

                        // Read response
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, _, recvError in
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
                                continuation.resume(throwing: UpdateError.agentRejected)
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
    case noReleaseAvailable
    case noAgentAssetFound
    case noDashboardAssetFound
    case invalidAssetURL
    case downloadFailed
    case githubAPIError
    case timeout
    case cancelled
    case agentRejected

    var errorDescription: String? {
        switch self {
        case .noReleaseAvailable: return "No release available on GitHub"
        case .noAgentAssetFound: return "No agent zip found in release assets"
        case .noDashboardAssetFound: return "No dashboard zip found in release assets"
        case .invalidAssetURL: return "Invalid asset download URL"
        case .downloadFailed: return "Failed to download update"
        case .githubAPIError: return "GitHub API request failed"
        case .timeout: return "Update request timed out"
        case .cancelled: return "Update cancelled"
        case .agentRejected: return "Agent rejected the update"
        }
    }
}
