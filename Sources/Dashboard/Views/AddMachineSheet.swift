import SwiftUI
import Shared

struct AddMachineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var portString: String = "\(BonjourConstants.defaultPort)"

    let onAdd: (String, UInt16) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Machine")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hostname or IP Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 100.64.0.5 or my-mac.ts.net", text: $host)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Port")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Port", text: $portString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let port = UInt16(portString) ?? BonjourConstants.defaultPort
                    onAdd(host.trimmingCharacters(in: .whitespacesAndNewlines), port)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
