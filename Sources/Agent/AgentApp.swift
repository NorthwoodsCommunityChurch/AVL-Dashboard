import SwiftUI
import Sparkle

@main
struct AgentApp: App {
    @NSApplicationDelegateAdaptor(AgentAppDelegate.self) var delegate
    @StateObject private var server = MetricsServer()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra(
            "AVL Dashboard Agent",
            systemImage: "gauge.with.dots.needle.bottom.50percent"
        ) {
            AgentMenuView(server: server, updater: updaterController.updater)
        }
    }
}

final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — also set via LSUIElement in Info.plist for bundled runs
        NSApp.setActivationPolicy(.accessory)
    }
}
