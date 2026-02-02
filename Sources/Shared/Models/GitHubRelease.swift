import Foundation

/// A release object from the GitHub REST API.
public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let prerelease: Bool
    public let htmlUrl: String
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
        case htmlUrl = "html_url"
        case assets
    }
}

/// An asset attached to a GitHub release.
public struct GitHubAsset: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

/// Comparable semantic version parsed from a tag like "v1.2.3-alpha".
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease { s += "-\(pre)" }
        return s
    }

    /// Parse a version string like "1.0.0", "v1.2.3", or "v1.0.0-alpha".
    public init?(_ string: String) {
        var s = string
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }

        let parts = s.split(separator: "-", maxSplits: 1)
        let versionPart = parts[0]
        let prePart = parts.count > 1 ? String(parts[1]) : nil

        let nums = versionPart.split(separator: ".").compactMap { Int($0) }
        guard nums.count >= 2 else { return nil }

        self.major = nums[0]
        self.minor = nums[1]
        self.patch = nums.count > 2 ? nums[2] : 0
        self.prerelease = prePart
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A prerelease version is always lower than the same version without prerelease
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false   // 1.0.0 > 1.0.0-alpha
        case (_, nil): return true    // 1.0.0-alpha < 1.0.0
        case let (l?, r?): return l < r  // alphabetical comparison of prerelease tags
        }
    }
}
