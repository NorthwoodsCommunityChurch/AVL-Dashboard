import SwiftUI
import ServiceManagement

struct AgentMenuView: View {
    @ObservedObject var server: MetricsServer
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack {
            if server.dashboardConnected {
                Label("Dashboard Connected", systemImage: "checkmark.circle.fill")
            } else {
                Label("No Dashboard Connected", systemImage: "xmark.circle")
            }

            if let port = server.activePort {
                Label("Port: \(port)", systemImage: "network")
                    .foregroundStyle(.secondary)
            }

            if !server.isRunning {
                Label("Server Not Running", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            Divider()

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Revert toggle if registration failed
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
