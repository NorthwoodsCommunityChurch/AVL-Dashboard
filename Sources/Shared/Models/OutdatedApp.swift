import Foundation

/// Represents an app that has an update available.
public struct OutdatedApp: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleIdentifier }

    /// The app's bundle identifier
    public let bundleIdentifier: String

    /// Display name of the app
    public let name: String

    /// Currently installed version
    public let installedVersion: String

    /// Latest available version
    public let latestVersion: String

    /// URL to download the update (if available from Sparkle feed)
    public let downloadURL: String?

    public init(
        bundleIdentifier: String,
        name: String,
        installedVersion: String,
        latestVersion: String,
        downloadURL: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.downloadURL = downloadURL
    }
}
