import SwiftUI
import Shared

/// A row of 3 widget slots at the bottom of a machine tile.
struct WidgetSlotRowView: View {
    @Binding var slots: [WidgetSlot]
    let onSave: () -> Void

    @State private var selectedSlotIndex: Int?
    @State private var showingPicker = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(slots.indices, id: \.self) { index in
                WidgetSlotView(slot: $slots[index]) {
                    selectedSlotIndex = index
                    showingPicker = true
                }
                .contextMenu {
                    if !slots[index].isEmpty {
                        Button("Remove", role: .destructive) {
                            slots[index].appIdentifier = nil
                            onSave()
                        }
                    }
                }
                .popover(isPresented: Binding(
                    get: { showingPicker && selectedSlotIndex == index },
                    set: { if !$0 { showingPicker = false } }
                )) {
                    AppPickerPopover(slot: $slots[index]) {
                        showingPicker = false
                        onSave()
                    }
                }
            }
        }
        .frame(height: 32)
    }
}
