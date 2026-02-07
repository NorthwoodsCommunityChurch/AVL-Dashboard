import Foundation
import AppKit
import Shared

/// An app discovered from the dock or known locations.
struct DiscoveredApp: Identifiable {
    let id: String  // bundleIdentifier
    let bundleIdentifier: String
    let name: String
    let iconData: Data
    let source: AppSource

    enum AppSource {
        case dock
        case applications
    }
}

/// Loads apps from the user's dock and /Applications folder for the widget picker.
@MainActor
final class AppCollectionLoader: ObservableObject {
    @Published var apps: [DiscoveredApp] = []
    @Published var isLoading = false

    func loadApps() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            var discovered: [DiscoveredApp] = []

            // Load dock apps first (these are the user's favorites)
            let dockApps = await loadDockApps()
            discovered.append(contentsOf: dockApps)

            // Load from /Applications folder
            let applicationApps = await loadApplicationsFolder()
            discovered.append(contentsOf: applicationApps)

            // Load AVL tools from development folder
            let avlApps = await loadAVLToolsFolder()
            discovered.append(contentsOf: avlApps)

            // Deduplicate by bundle identifier (dock apps take priority)
            var seen = Set<String>()
            discovered = discovered.filter { app in
                if seen.contains(app.bundleIdentifier) { return false }
                seen.insert(app.bundleIdentifier)
                return true
            }

            // Sort alphabetically
            discovered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            apps = discovered
            isLoading = false
        }
    }

    private func loadDockApps() async -> [DiscoveredApp] {
        let dockPlistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.dock.plist"

        guard let dockData = try? Data(contentsOf: URL(fileURLWithPath: dockPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: dockData, format: nil) as? [String: Any],
              let persistentApps = plist["persistent-apps"] as? [[String: Any]] else {
            return []
        }

        var apps: [DiscoveredApp] = []

        for item in persistentApps {
            guard let tileData = item["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let cfURLString = fileData["_CFURLString"] as? String else {
                continue
            }

            // Parse file:// URL to path
            guard let url = URL(string: cfURLString) else { continue }

            if let app = createDiscoveredApp(from: url, source: .dock) {
                apps.append(app)
            }
        }

        return apps
    }

    private func loadApplicationsFolder() async -> [DiscoveredApp] {
        let applicationsPath = "/Applications"
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: applicationsPath) else {
            return []
        }

        var apps: [DiscoveredApp] = []

        for item in contents {
            guard item.hasSuffix(".app") else { continue }
            let url = URL(fileURLWithPath: applicationsPath).appendingPathComponent(item)

            if let app = createDiscoveredApp(from: url, source: .applications) {
                apps.append(app)
            }
        }

        return apps
    }

    private func loadAVLToolsFolder() async -> [DiscoveredApp] {
        // Scan the VS Code development folder for built .app bundles
        let vsCodePath = NSHomeDirectory() + "/Library/CloudStorage/OneDrive-NorthwoodsCommunityChurch/VS Code"
        let fileManager = FileManager.default

        guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: vsCodePath) else {
            return []
        }

        var apps: [DiscoveredApp] = []

        for projectDir in projectDirs {
            let projectPath = vsCodePath + "/" + projectDir

            // Check common build output locations
            let buildPaths = [
                projectPath + "/build",
                projectPath + "/build/Build/Products/Release",
                projectPath + "/build/Build/Products/Debug",
                projectPath + "/.build/release"
            ]

            for buildPath in buildPaths {
                guard let contents = try? fileManager.contentsOfDirectory(atPath: buildPath) else {
                    continue
                }

                for item in contents {
                    guard item.hasSuffix(".app") else { continue }
                    let url = URL(fileURLWithPath: buildPath).appendingPathComponent(item)

                    if let app = createDiscoveredApp(from: url, source: .applications) {
                        apps.append(app)
                    }
                }
            }
        }

        return apps
    }

    private func createDiscoveredApp(from url: URL, source: DiscoveredApp.AppSource) -> DiscoveredApp? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }

        // Get app name
        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        // Extract icon
        guard let iconData = extractIcon(from: url, size: 48) else {
            return nil
        }

        return DiscoveredApp(
            id: bundleId,
            bundleIdentifier: bundleId,
            name: name,
            iconData: iconData,
            source: source
        )
    }

    private func extractIcon(from appURL: URL, size: Int) -> Data? {
        // Use NSWorkspace to get the app icon (handles all icon types)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return icon.pngData(size: CGSize(width: size, height: size))
    }
}

extension NSImage {
    func pngData(size: CGSize) -> Data? {
        let resized = NSImage(size: size)
        resized.lockFocus()
        self.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
