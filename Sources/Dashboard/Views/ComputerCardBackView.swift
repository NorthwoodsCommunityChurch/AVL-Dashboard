import SwiftUI
import Shared

/// Back face of a computer card with settings.
struct ComputerCardBackView: View {
    @Bindable var machine: MachineViewModel
    var needsUpdate: Bool = false
    var onUpdate: (() -> Void)?
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

            // Network interfaces (MAC addresses, selectable)
            ForEach(machine.networks, id: \.interfaceName) { network in
                HStack(spacing: 4) {
                    Image(systemName: network.interfaceType == "Wi-Fi" ? "wifi" : "cable.connector.horizontal")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(network.interfaceName): \(network.macAddress)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            // Agent version + update
            HStack(spacing: 4) {
                Image(systemName: "app.badge")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("Agent v\(machine.agentVersion ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)

                if needsUpdate {
                    if machine.isUpdating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button {
                            onUpdate?()
                        } label: {
                            Label("Update", systemImage: "arrow.down.circle")
                                .font(.caption2)
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let error = machine.updateError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
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
