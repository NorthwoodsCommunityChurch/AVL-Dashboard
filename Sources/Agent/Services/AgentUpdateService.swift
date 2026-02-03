import Foundation
import Shared

/// Periodically checks GitHub for new agent releases and auto-applies updates.
final class AgentUpdateService: ObservableObject {
    private let owner = "NorthwoodsCommunityChurch"
    private let repo = "AVL-Dashboard"

    @Published private(set) var isUpdating = false
    @Published private(set) var lastError: String?
    @Published private(set) var latestVersionString: String?

    private var lastCheck: Date?
    private var checkTask: Task<Void, Never>?

    /// The current app version parsed as a SemanticVersion.
    var currentVersion: SemanticVersion? {
        SemanticVersion(AppVersion.current)
    }

    init() {
        startPeriodicChecks()
    }

    /// Start periodic background checks (every 30 minutes).
    private func startPeriodicChecks() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            // Initial check shortly after launch
            try? await Task.sleep(for: .seconds(5))
            await self?.checkAndUpdate()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                await self?.checkAndUpdate()
            }
        }
    }

    /// Force an immediate check, ignoring the cache.
    func forceCheck() async {
        lastCheck = nil
        await checkAndUpdate()
    }

    /// Check GitHub for a newer agent release and auto-apply if found.
    func checkAndUpdate() async {
        // Cache for 15 minutes to avoid redundant calls
        if let last = lastCheck, Date().timeIntervalSince(last) < 900 {
            return
        }

        do {
            let releases = try await fetchReleases()

            let best = releases
                .compactMap { release -> (GitHubRelease, SemanticVersion)? in
                    guard let v = SemanticVersion(release.tagName) else { return nil }
                    return (release, v)
                }
                .sorted { $0.1 > $1.1 }
                .first

            lastCheck = Date()

            guard let (release, latestVersion) = best else { return }

            await MainActor.run {
                self.latestVersionString = latestVersion.description
                self.lastError = nil
            }

            guard let current = currentVersion, latestVersion > current else { return }

            // Find agent zip asset
            let agentAsset = release.assets.first {
                $0.name.lowercased().contains("agent") && $0.name.hasSuffix(".zip")
            }
            guard let asset = agentAsset else { return }

            // Download and apply
            await MainActor.run { self.isUpdating = true }

            let zipData = try await downloadAsset(url: asset.browserDownloadUrl)
            try UpdateManager.shared.applyUpdate(zipData: zipData)
            // If applyUpdate succeeds, the app will terminate and relaunch.
            // If we reach here, something unexpected happened.
        } catch {
            await MainActor.run {
                self.isUpdating = false
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - GitHub API

    private func fetchReleases() async throws -> [GitHubRelease] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentUpdateError.githubAPIError
        }

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func downloadAsset(url: String) async throws -> Data {
        guard let assetURL = URL(string: url) else {
            throw AgentUpdateError.invalidAssetURL
        }

        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentUpdateError.downloadFailed
        }

        return data
    }
}

private enum AgentUpdateError: Error, LocalizedError {
    case githubAPIError
    case invalidAssetURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .githubAPIError: return "GitHub API request failed"
        case .invalidAssetURL: return "Invalid asset download URL"
        case .downloadFailed: return "Failed to download update"
        }
    }
}
