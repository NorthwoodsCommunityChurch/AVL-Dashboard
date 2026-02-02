import SwiftUI
import Shared

/// Container that manages a 3D flip between front and back card faces.
struct FlipCardView: View {
    @Bindable var machine: MachineViewModel
    let onDelete: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            // Front face
            ComputerCardView(machine: machine)
                .opacity(machine.isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(machine.isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )

            // Back face
            ComputerCardBackView(
                machine: machine,
                onDone: {
                    onSave()
                    withAnimation(.spring(duration: 0.4)) {
                        machine.isFlipped = false
                    }
                },
                onDelete: onDelete
            )
            .opacity(machine.isFlipped ? 1 : 0)
            .rotation3DEffect(
                .degrees(machine.isFlipped ? 0 : -180),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .frame(height: 155)
        .onTapGesture {
            if !machine.isFlipped {
                withAnimation(.spring(duration: 0.4)) {
                    machine.isFlipped = true
                }
            }
        }
    }
}
