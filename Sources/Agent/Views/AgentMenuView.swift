import SwiftUI

struct AgentMenuView: View {
    @ObservedObject var server: MetricsServer

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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
