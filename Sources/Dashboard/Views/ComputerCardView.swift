import SwiftUI
import Shared

/// Front face of a computer card showing live metrics.
struct ComputerCardView: View {
    let machine: MachineViewModel
    var needsUpdate: Bool = false
    @Environment(\.openURL) private var openURL

    private var cpuColor: Color {
        if machine.cpuUsage >= 90 { return .red }
        if machine.cpuUsage >= 60 { return .orange }
        if machine.cpuUsage >= 30 { return .yellow }
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
        if t >= machine.thresholds.critical { return .red }
        if t >= machine.thresholds.warning { return .orange }
        if t >= machine.thresholds.good { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 4) {
            // Machine name — tap to screen share
            Button {
                if let ip = machine.networkInfo?.ipAddress,
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
            .disabled(machine.networkInfo?.ipAddress == nil)
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
                    label: machine.cpuTemp >= 0 ? "\(Int(machine.cpuTemp))°" : "--",
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

            // Metric tiles
            metricTile {
                Label(machine.uptimeSeconds.formattedUptime, systemImage: "clock")
            }

            if let network = machine.networkInfo {
                metricTile {
                    Label("\(network.ipAddress) (\(network.interfaceType))", systemImage: "network")
                        .lineLimit(1)
                }
            }

            HStack(spacing: 4) {
                metricTile {
                    HStack(spacing: 3) {
                        Image(systemName: machine.fileVaultEnabled ? "lock.fill" : "lock.open")
                            .font(.system(size: 9))
                        Text(machine.fileVaultEnabled ? "FileVault" : "No FV")
                    }
                    .foregroundStyle(machine.fileVaultEnabled ? .orange : .green)
                }

                if let mac = machine.networkInfo?.macAddress {
                    metricTile {
                        Text(mac)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }

            Spacer(minLength: 0)
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
