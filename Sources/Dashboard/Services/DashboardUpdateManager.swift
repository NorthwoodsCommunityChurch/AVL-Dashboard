import Foundation
import AppKit

/// Handles extracting a downloaded zip and replacing the running Dashboard app bundle.
/// Uses a shell trampoline script that outlives the current process to swap the bundle and relaunch.
final class DashboardUpdateManager {
    static let shared = DashboardUpdateManager()

    private let maxUpdateSize = 50 * 1024 * 1024 // 50 MB

    private init() {}

    /// Process a downloaded zip file: extract, locate .app, write trampoline, terminate.
    func applyUpdate(zipData: Data) throws {
        guard zipData.count <= maxUpdateSize else {
            throw DashboardUpdateError.fileTooLarge
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write zip to temp
        let zipPath = tempDir.appendingPathComponent("update.zip")
        try zipData.write(to: zipPath)

        // Unzip
        let unzipDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipPath.path, "-d", unzipDir.path]
        unzip.standardOutput = Pipe()
        unzip.standardError = Pipe()
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            throw DashboardUpdateError.unzipFailed
        }

        // Find the .app bundle in extracted contents
        guard let appBundle = findAppBundle(in: unzipDir) else {
            throw DashboardUpdateError.noAppBundleFound
        }

        // Current app bundle path
        let currentBundle = Bundle.main.bundlePath

        // Write and execute trampoline script
        let trampolinePath = tempDir.appendingPathComponent("trampoline.sh")
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/bash
        # Wait for the dashboard process to exit
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.5
        done

        # Remove old app
        rm -rf "\(currentBundle)"

        # Move new app into place
        mv "\(appBundle.path)" "\(currentBundle)"

        # Re-sign ad hoc
        /usr/bin/codesign --force --deep --sign - "\(currentBundle)" 2>/dev/null

        # Relaunch
        open "\(currentBundle)"

        # Clean up temp directory
        rm -rf "\(tempDir.path)"
        """

        try script.write(to: trampolinePath, atomically: true, encoding: .utf8)

        // Make executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", trampolinePath.path]
        try chmod.run()
        chmod.waitUntilExit()

        // Launch trampoline as detached process
        let trampoline = Process()
        trampoline.executableURL = URL(fileURLWithPath: "/bin/bash")
        trampoline.arguments = [trampolinePath.path]
        trampoline.standardOutput = FileHandle.nullDevice
        trampoline.standardError = FileHandle.nullDevice
        trampoline.environment = ProcessInfo.processInfo.environment
        try trampoline.run()

        // Terminate self so the trampoline can replace us
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Recursively search for a .app bundle in the given directory.
    private func findAppBundle(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app" {
                let macosDir = url.appendingPathComponent("Contents/MacOS")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: macosDir.path, isDirectory: &isDir), isDir.boolValue {
                    return url
                }
            }
        }

        return nil
    }
}

enum DashboardUpdateError: Error, LocalizedError {
    case fileTooLarge
    case unzipFailed
    case noAppBundleFound

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "Update file exceeds 50MB limit"
        case .unzipFailed: return "Failed to extract update archive"
        case .noAppBundleFound: return "No .app bundle found in update archive"
        }
    }
}
