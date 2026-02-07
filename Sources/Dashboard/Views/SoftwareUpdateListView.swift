import SwiftUI
import Shared

/// Full-screen view showing software update status for a machine.
struct SoftwareUpdateListView: View {
    let machine: MachineViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Software Updates")
                        .font(.headline)
                    Text(machine.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(.bar)

            Divider()

            if machine.outdatedApps.isEmpty {
                // All apps up to date
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("All Apps Up to Date")
                        .font(.title2)
                    Text("Apps with Sparkle update feeds are checked daily at 3 AM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List of apps needing updates
                List {
                    Section {
                        ForEach(machine.outdatedApps) { app in
                            AppUpdateRow(app: app, status: .outdated)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.orange)
                            Text("\(machine.outdatedApps.count) Update\(machine.outdatedApps.count == 1 ? "" : "s") Available")
                        }
                    }
                }
                .listStyle(.inset)
            }

            // Footer note
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("Only apps with Sparkle update feeds are monitored.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

/// Status of an app's update check
private enum AppUpdateStatus {
    case upToDate
    case outdated
    case unknown

    var color: Color {
        switch self {
        case .upToDate: return .green
        case .outdated: return .orange
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .upToDate: return "checkmark.circle.fill"
        case .outdated: return "arrow.down.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Row displaying a single app's update status
private struct AppUpdateRow: View {
    let app: OutdatedApp
    let status: AppUpdateStatus
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.icon)
                .font(.title2)
                .foregroundStyle(status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)

                HStack(spacing: 4) {
                    Text("Installed: \(app.installedVersion)")
                        .foregroundStyle(.secondary)

                    if status == .outdated {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(app.latestVersion)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if let urlString = app.downloadURL, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Label("Download", systemImage: "arrow.down.to.line")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
