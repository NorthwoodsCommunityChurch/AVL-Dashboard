import Foundation

/// Represents an app that can be assigned to a widget slot.
public struct AppIdentifier: Codable, Sendable, Equatable, Hashable {
    /// The app's bundle identifier (e.g., "com.apple.Safari")
    public let bundleIdentifier: String

    /// Display name of the app
    public let name: String

    /// PNG icon data cached at assignment time (48x48)
    public let iconData: Data?

    public init(bundleIdentifier: String, name: String, iconData: Data? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.iconData = iconData
    }
}
