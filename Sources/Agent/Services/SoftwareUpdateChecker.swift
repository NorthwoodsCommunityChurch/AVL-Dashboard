import Foundation
import Shared

/// Known AVL apps that don't use Sparkle but should be monitored.
private struct KnownAVLApp {
    let bundleIdentifier: String
    let name: String
    let downloadURL: String
    /// If true, we can check for updates programmatically
    let canCheckUpdates: Bool

    static let registry: [KnownAVLApp] = [
        // ProPresenter by Renewed Vision - we can scrape their download page
        KnownAVLApp(
            bundleIdentifier: "com.renewedvision.ProPresenter7",
            name: "ProPresenter",
            downloadURL: "https://renewedvision.com/propresenter/download/",
            canCheckUpdates: true
        ),
        // Blackmagic apps - no programmatic update check available
        KnownAVLApp(
            bundleIdentifier: "com.blackmagic-design.DesktopVideoSetup",
            name: "Blackmagic Desktop Video",
            downloadURL: "https://www.blackmagicdesign.com/support/family/capture-and-playback",
            canCheckUpdates: false
        ),
        KnownAVLApp(
            bundleIdentifier: "com.blackmagic-design.ATEMSoftwareControl",
            name: "ATEM Software Control",
            downloadURL: "https://www.blackmagicdesign.com/support/family/atem-live-production-switchers",
            canCheckUpdates: false
        ),
        KnownAVLApp(
            bundleIdentifier: "com.blackmagic-design.HyperDeckSetup",
            name: "Blackmagic HyperDeck",
            downloadURL: "https://www.blackmagicdesign.com/support/family/hyperdecks",
            canCheckUpdates: false
        ),
    ]
}

/// Checks installed applications for available updates by querying Sparkle feeds.
/// Also monitors known AVL apps that don't use Sparkle.
/// Runs daily at 3 AM (or on first boot if missed).
actor SoftwareUpdateChecker {
    private var outdatedApps: [OutdatedApp] = []
    private var lastCheckDate: Date?
    private var checkTask: Task<Void, Never>?

    /// The hour to run the daily check (24-hour format)
    private let checkHour = 3

    init() {
        startScheduler()
    }

    deinit {
        checkTask?.cancel()
    }

    /// Returns the current list of outdated apps (from last check)
    func getOutdatedApps() -> [OutdatedApp] {
        return outdatedApps
    }

    /// Starts the scheduler that runs checks at 3 AM daily
    private func startScheduler() {
        checkTask = Task {
            // Check immediately on first launch if we haven't checked today
            if shouldCheckNow() {
                await performCheck()
            }

            // Then schedule daily checks
            while !Task.isCancelled {
                let nextCheck = timeUntilNextCheck()
                try? await Task.sleep(nanoseconds: UInt64(nextCheck * 1_000_000_000))

                if Task.isCancelled { break }
                await performCheck()
            }
        }
    }

    /// Returns true if we should check immediately (haven't checked today)
    private func shouldCheckNow() -> Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return !Calendar.current.isDateInToday(lastCheck)
    }

    /// Returns seconds until the next 3 AM
    private func timeUntilNextCheck() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = checkHour
        components.minute = 0
        components.second = 0

        guard var nextCheck = calendar.date(from: components) else {
            return 3600 // Fallback: 1 hour
        }

        // If 3 AM has already passed today, schedule for tomorrow
        if nextCheck <= now {
            nextCheck = calendar.date(byAdding: .day, value: 1, to: nextCheck) ?? now
        }

        return nextCheck.timeIntervalSince(now)
    }

    /// Performs the update check for all installed apps
    private func performCheck() async {
        print("[SoftwareUpdateChecker] Starting daily update check...")

        var outdated: [OutdatedApp] = []

        // Check Sparkle-based apps
        let sparkleApps = scanInstalledApps()
        for app in sparkleApps {
            if let result = await checkForUpdate(app: app) {
                outdated.append(result)
            }
        }

        // Check known AVL apps
        let knownApps = await scanKnownAVLApps()
        outdated.append(contentsOf: knownApps)

        self.outdatedApps = outdated
        self.lastCheckDate = Date()

        print("[SoftwareUpdateChecker] Check complete. Found \(outdated.count) apps to monitor.")
    }

    /// Scans /Applications for known AVL apps that don't use Sparkle
    private func scanKnownAVLApps() async -> [OutdatedApp] {
        let fileManager = FileManager.default
        let applicationsPath = "/Applications"

        guard let contents = try? fileManager.contentsOfDirectory(atPath: applicationsPath) else {
            return []
        }

        var results: [OutdatedApp] = []

        for item in contents {
            guard item.hasSuffix(".app") else { continue }

            let appPath = applicationsPath + "/" + item
            let infoPlistPath = appPath + "/Contents/Info.plist"

            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let bundleId = plist["CFBundleIdentifier"] as? String else {
                continue
            }

            // Check if this app is in our known AVL apps registry
            if let knownApp = KnownAVLApp.registry.first(where: { $0.bundleIdentifier == bundleId }) {
                let installedVersion = plist["CFBundleShortVersionString"] as? String
                    ?? plist["CFBundleVersion"] as? String
                    ?? "Unknown"

                // Try to check for updates if supported
                if knownApp.canCheckUpdates {
                    if let outdatedApp = await checkKnownAppForUpdate(
                        knownApp: knownApp,
                        installedVersion: installedVersion
                    ) {
                        results.append(outdatedApp)
                    }
                    // If nil returned, app is up to date - don't add to list
                } else {
                    // Can't check updates - add as monitored app
                    results.append(OutdatedApp(
                        bundleIdentifier: knownApp.bundleIdentifier,
                        name: knownApp.name,
                        installedVersion: installedVersion,
                        latestVersion: "Check website",
                        downloadURL: knownApp.downloadURL
                    ))
                }
            }
        }

        return results
    }

    /// Checks a known AVL app for updates using app-specific methods
    private func checkKnownAppForUpdate(knownApp: KnownAVLApp, installedVersion: String) async -> OutdatedApp? {
        switch knownApp.bundleIdentifier {
        case "com.renewedvision.ProPresenter7":
            return await checkProPresenterUpdate(knownApp: knownApp, installedVersion: installedVersion)
        default:
            return nil
        }
    }

    /// Checks ProPresenter for updates by scraping their download page
    private func checkProPresenterUpdate(knownApp: KnownAVLApp, installedVersion: String) async -> OutdatedApp? {
        guard let url = URL(string: knownApp.downloadURL) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }

            // Look for Mac download URLs like: ProPresenter_21.2_352452646.zip
            // Pattern: ProPresenter_(\d+\.\d+(?:\.\d+)?)_
            let pattern = "ProPresenter_(\\d+\\.\\d+(?:\\.\\d+)?)_\\d+\\.zip"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let versionRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            let latestVersion = String(html[versionRange])

            // Compare versions
            if isVersion(installedVersion, lessThan: latestVersion) {
                // Find the full download URL
                let downloadPattern = "https://renewedvision\\.com/downloads//propresenter/mac/ProPresenter_\(latestVersion)_\\d+\\.zip"
                var downloadURL = knownApp.downloadURL
                if let downloadRegex = try? NSRegularExpression(pattern: downloadPattern, options: []),
                   let downloadMatch = downloadRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                   let downloadRange = Range(downloadMatch.range, in: html) {
                    downloadURL = String(html[downloadRange])
                }

                return OutdatedApp(
                    bundleIdentifier: knownApp.bundleIdentifier,
                    name: knownApp.name,
                    installedVersion: installedVersion,
                    latestVersion: latestVersion,
                    downloadURL: downloadURL
                )
            }

            // Up to date - return nil (don't show in list)
            return nil
        } catch {
            print("[SoftwareUpdateChecker] Failed to check ProPresenter updates: \(error)")
            // On error, fall back to manual check
            return OutdatedApp(
                bundleIdentifier: knownApp.bundleIdentifier,
                name: knownApp.name,
                installedVersion: installedVersion,
                latestVersion: "Check website",
                downloadURL: knownApp.downloadURL
            )
        }
    }

    /// Scans /Applications for apps with Sparkle feed URLs
    private func scanInstalledApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let applicationsPath = "/Applications"

        guard let contents = try? fileManager.contentsOfDirectory(atPath: applicationsPath) else {
            return []
        }

        var apps: [InstalledApp] = []

        for item in contents {
            guard item.hasSuffix(".app") else { continue }

            let appPath = applicationsPath + "/" + item
            let infoPlistPath = appPath + "/Contents/Info.plist"

            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
                continue
            }

            // Get Sparkle feed URL
            guard let feedURL = plist["SUFeedURL"] as? String else {
                continue // Skip apps without Sparkle
            }

            // Get app info
            let bundleId = plist["CFBundleIdentifier"] as? String ?? ""
            let name = plist["CFBundleDisplayName"] as? String
                ?? plist["CFBundleName"] as? String
                ?? item.replacingOccurrences(of: ".app", with: "")
            let version = plist["CFBundleShortVersionString"] as? String
                ?? plist["CFBundleVersion"] as? String
                ?? "0"

            apps.append(InstalledApp(
                bundleIdentifier: bundleId,
                name: name,
                installedVersion: version,
                sparkleFeedURL: feedURL
            ))
        }

        return apps
    }

    /// Checks a single app for updates by fetching its Sparkle feed
    private func checkForUpdate(app: InstalledApp) async -> OutdatedApp? {
        guard let feedURL = URL(string: app.sparkleFeedURL) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)

            // Parse the Sparkle appcast XML
            let parser = SparkleAppcastParser(data: data)
            guard let latestVersion = parser.latestVersion,
                  let downloadURL = parser.downloadURL else {
                return nil
            }

            // Compare versions
            if isVersion(app.installedVersion, lessThan: latestVersion) {
                return OutdatedApp(
                    bundleIdentifier: app.bundleIdentifier,
                    name: app.name,
                    installedVersion: app.installedVersion,
                    latestVersion: latestVersion,
                    downloadURL: downloadURL
                )
            }
        } catch {
            // Silently skip apps that fail (network issues, invalid feeds, etc.)
        }

        return nil
    }

    /// Simple version comparison (handles x.y.z format)
    private func isVersion(_ installed: String, lessThan latest: String) -> Bool {
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(installedParts.count, latestParts.count) {
            let installedPart = i < installedParts.count ? installedParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if installedPart < latestPart { return true }
            if installedPart > latestPart { return false }
        }

        return false
    }
}

/// Represents an installed app with Sparkle support
private struct InstalledApp {
    let bundleIdentifier: String
    let name: String
    let installedVersion: String
    let sparkleFeedURL: String
}

/// Simple parser for Sparkle appcast XML
private class SparkleAppcastParser: NSObject, XMLParserDelegate {
    var latestVersion: String?
    var downloadURL: String?

    private var currentElement = ""
    private var foundFirstItem = false

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        // Only process the first <item> (latest version)
        if elementName == "item" {
            if foundFirstItem {
                parser.abortParsing() // Stop after first item
            }
            foundFirstItem = true
        }

        // Look for enclosure element with download URL
        if elementName == "enclosure", foundFirstItem {
            if let url = attributeDict["url"] {
                downloadURL = url
            }
            // Sparkle version can be in enclosure attributes
            if let version = attributeDict["sparkle:version"] ?? attributeDict["sparkle:shortVersionString"] {
                latestVersion = version
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard foundFirstItem else { return }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Fallback version detection from sparkle:version element
        if currentElement == "sparkle:version" || currentElement == "sparkle:shortVersionString" {
            latestVersion = trimmed
        }
    }
}
