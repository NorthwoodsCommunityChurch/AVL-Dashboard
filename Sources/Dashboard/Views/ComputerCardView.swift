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

    private func gpuUsageColor(_ usage: Double) -> Color {
        if usage >= 90 { return .red }
        if usage >= 70 { return .orange }
        if usage >= 40 { return .yellow }
        return .green
    }

    private func gpuTempColor(_ temp: Double) -> Color {
        guard temp >= 0 else { return .gray }
        if temp >= 90 { return .red }
        if temp >= 75 { return .orange }
        if temp >= 55 { return .yellow }
        return .green
    }

    /// Abbreviate GPU name for the ring subtitle (e.g. "AMD Radeon RX 580" → "RX 580").
    private func gpuShortName(_ name: String) -> String {
        if let range = name.range(of: "RX ", options: .caseInsensitive) {
            return String(name[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = name.range(of: "Pro ", options: .caseInsensitive) {
            return String(name[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Last resort: take last word
        return name.components(separatedBy: " ").suffix(2).joined(separator: " ")
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

            // GPU dual rings (only if enabled and data available)
            if machine.shouldShowGPURings {
                HStack(spacing: 8) {
                    ForEach(Array(machine.gpus.prefix(3).enumerated()), id: \.offset) { _, gpu in
                        DualConcentricRingView(
                            outerValue: gpu.usagePercent,
                            outerMaxValue: 100,
                            outerColor: gpuUsageColor(gpu.usagePercent),
                            innerValue: gpu.temperatureCelsius,
                            innerMaxValue: 120,
                            innerColor: gpuTempColor(gpu.temperatureCelsius),
                            label: gpu.temperatureCelsius >= 0 ? "\(Int(gpu.temperatureCelsius))\u{00B0}" : "--",
                            subtitle: gpuShortName(gpu.name),
                            isOnline: machine.isOnline
                        )
                    }
                }
                .frame(height: 50)
            }

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
            .frame(height: machine.shouldShowGPURings ? 58 : 78)
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
