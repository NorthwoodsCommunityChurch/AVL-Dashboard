import SwiftUI
import Shared

/// Popover for editing global dashboard settings (temperature and CPU color thresholds).
struct SettingsPopoverView: View {
    @Binding var settings: DashboardSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dashboard Settings")
                .font(.headline)

            thresholdSection(
                title: "TEMP ALERTS (\u{00B0}C)",
                thresholds: $settings.tempThresholds
            )

            thresholdSection(
                title: "CPU ALERTS (%)",
                thresholds: $settings.cpuThresholds
            )
        }
        .padding()
        .frame(width: 240)
    }

    private func thresholdSection(title: String, thresholds: Binding<MachineThresholds>) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                thresholdPill(color: .green, label: "Good", value: thresholds.good)
                thresholdPill(color: .yellow, label: "Warn", value: thresholds.warning)
                thresholdPill(color: .red, label: "Crit", value: thresholds.critical)
            }
        }
    }

    private func thresholdPill(color: Color, label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            TextField(
                label,
                value: value,
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption2)
            .frame(minWidth: 30)
        }
    }
}
