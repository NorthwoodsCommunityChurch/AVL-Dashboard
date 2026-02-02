import SwiftUI
import Shared

/// Back face of a computer card with settings.
struct ComputerCardBackView: View {
    @Bindable var machine: MachineViewModel
    let onDone: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 6) {
            // Display Name
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                TextField("Display Name", text: $machine.displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Temperature Thresholds — compact horizontal row
            VStack(spacing: 3) {
                Text("TEMP ALERTS (°C)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    thresholdPill(color: .green, label: "Good", value: $machine.thresholds.good)
                    thresholdPill(color: .yellow, label: "Warn", value: $machine.thresholds.warning)
                    thresholdPill(color: .red, label: "Crit", value: $machine.thresholds.critical)
                }
            }

            // MAC Address (read-only)
            if let mac = machine.networkInfo?.macAddress {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(mac)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack {
                Button("Done") {
                    machine.thresholds.validate()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.mini)
            }
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
        .alert("Remove Machine", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Remove \(machine.displayName) from the dashboard? It will reappear if the agent is still running.")
        }
    }

    /// Compact threshold field: colored dot + tiny number field.
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
