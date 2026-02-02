import SwiftUI

@main
struct AgentApp: App {
    @NSApplicationDelegateAdaptor(AgentAppDelegate.self) var delegate
    @StateObject private var server = MetricsServer()

    var body: some Scene {
        MenuBarExtra(
            "Computer Dashboard Agent",
            systemImage: "gauge.with.dots.needle.bottom.50percent"
        ) {
            AgentMenuView(server: server)
        }
    }
}

final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — also set via LSUIElement in Info.plist for bundled runs
        NSApp.setActivationPolicy(.accessory)
    }
}
