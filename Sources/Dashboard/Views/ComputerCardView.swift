import SwiftUI
import Shared

/// Front face of a computer card showing live metrics.
struct ComputerCardView: View {
    @Bindable var machine: MachineViewModel
    let settings: DashboardSettings
    var needsUpdate: Bool = false
    let onSave: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var copiedNetwork: String?
    @State private var showingSoftwareUpdates = false

    private var cpuColor: Color {
        let u = machine.cpuUsage
        if u >= settings.cpuThresholds.critical { return .red }
        if u >= settings.cpuThresholds.warning { return .orange }
        if u >= settings.cpuThresholds.good { return .yellow }
        return .green
    }

    private var netColor: Color {
        let bps = machine.networkBytesPerSec
        if bps >= 10_000_000 { return .blue }        // 10+ MB/s
        if bps >= 1_000_000 { return .cyan }          // 1+ MB/s
        if bps >= 100_000 { return .teal }             // 100+ KB/s
        return .mint
    }

    private var tempColor: Color {
        let t = machine.cpuTemp
        guard t >= 0 else { return .gray }
        if t >= settings.tempThresholds.critical { return .red }
        if t >= settings.tempThresholds.warning { return .orange }
        if t >= settings.tempThresholds.good { return .yellow }
        return .green
    }

    // App update status - distinguish between confirmed updates, monitored apps, and all up to date
    private var confirmedUpdates: [OutdatedApp] {
        machine.outdatedApps.filter { $0.latestVersion != "Check website" }
    }

    private var monitoredApps: [OutdatedApp] {
        machine.outdatedApps.filter { $0.latestVersion == "Check website" }
    }

    private var appStatusIcon: String {
        if !confirmedUpdates.isEmpty {
            return "arrow.down.circle.fill"
        } else if !monitoredApps.isEmpty {
            return "eye.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var appStatusText: String {
        if !confirmedUpdates.isEmpty {
            return "\(confirmedUpdates.count) Update\(confirmedUpdates.count == 1 ? "" : "s") Available"
        } else if !monitoredApps.isEmpty {
            return "\(monitoredApps.count) App\(monitoredApps.count == 1 ? "" : "s") Monitored"
        } else {
            return "Apps Up to Date"
        }
    }

    private var appStatusColor: Color {
        if !confirmedUpdates.isEmpty {
            return .orange
        } else if !monitoredApps.isEmpty {
            return .blue
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            // Machine name — tap to screen share
            Button {
                if let ip = machine.primaryNetwork?.ipAddress,
                   let url = URL(string: "vnc://\(ip)") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 3) {
                    if machine.isManual {
                        Image(systemName: machine.isBonjourActive ? "wifi" : "globe")
                            .font(.system(size: 8))
                    }

                    Text(machine.displayName)
                        .font(.system(.caption, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(machine.primaryNetwork?.ipAddress == nil)
            .padding(.bottom, 2)

            // Three rings — Apple Watch style
            HStack(spacing: 8) {
                MetricRingView(
                    value: machine.cpuUsage,
                    maxValue: 100,
                    color: cpuColor,
                    label: "\(Int(machine.cpuUsage))%",
                    icon: "cpu",
                    isOnline: machine.isOnline
                )

                MetricRingView(
                    value: machine.cpuTemp,
                    maxValue: 120,
                    color: tempColor,
                    label: machine.cpuTemp >= 0 ? "\(Int(machine.cpuTemp))\u{00B0}" : "--",
                    icon: "thermometer.medium",
                    isOnline: machine.isOnline
                )

                MetricRingView(
                    value: min(machine.networkBytesPerSec, 100_000_000),
                    maxValue: 100_000_000,
                    color: netColor,
                    label: machine.networkBytesPerSec.formattedBytesPerSec,
                    icon: "arrow.up.arrow.down",
                    isOnline: machine.isOnline
                )
            }
            .frame(height: 50)

            // Metric tiles in scrollable area
            ScrollView {
                VStack(spacing: 4) {
                    metricTile {
                        Label(machine.uptimeSeconds.formattedUptime, systemImage: "clock")
                    }

                    metricTile {
                        HStack(spacing: 3) {
                            Image(systemName: machine.fileVaultEnabled ? "lock.fill" : "lock.open")
                                .font(.system(size: 9))
                            Text(machine.fileVaultEnabled ? "FileVault" : "No FV")
                        }
                        .foregroundStyle(machine.fileVaultEnabled ? Color.orange : Color.green)
                    }

                    // Software update status
                    Button {
                        showingSoftwareUpdates = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: appStatusIcon)
                                .font(.system(size: 9))
                            Text(appStatusText)
                            Spacer(minLength: 0)
                        }
                        .font(.caption2)
                        .foregroundStyle(appStatusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    ForEach(machine.networks, id: \.interfaceName) { network in
                        Button {
                            let text = "\(network.ipAddress)  \(network.macAddress)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            copiedNetwork = network.interfaceName
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedNetwork == network.interfaceName {
                                    copiedNetwork = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedNetwork == network.interfaceName
                                      ? "checkmark.circle.fill"
                                      : (network.interfaceType == "Wi-Fi" ? "wifi" : "cable.connector.horizontal"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(copiedNetwork == network.interfaceName ? Color.green : Color.secondary)
                                Text("\(network.ipAddress) (\(network.interfaceType))")
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(network.macAddress)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Copy IP and MAC to clipboard")
                    }
                }
            }
            .frame(height: 78)  // ~3 lines visible (26pt each)
            .scrollIndicators(.hidden)

            // Widget slots
            WidgetSlotRowView(slots: $machine.widgetSlots, onSave: onSave)
        }
        .padding(8)
        .frame(minWidth: 140, maxWidth: .infinity, maxHeight: .infinity)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .overlay(alignment: .topTrailing) {
            if needsUpdate {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .background(Circle().fill(.thickMaterial).padding(1))
                    .offset(x: 4, y: -4)
            }
        }
        .sheet(isPresented: $showingSoftwareUpdates) {
            SoftwareUpdateListView(machine: machine)
        }
    }

    private func metricTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
