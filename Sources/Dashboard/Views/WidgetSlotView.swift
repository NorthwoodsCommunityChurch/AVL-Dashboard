import SwiftUI
import Shared

/// A single widget slot that displays either a plus button (empty) or an app icon (assigned).
struct WidgetSlotView: View {
    @Binding var slot: WidgetSlot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let app = slot.appIdentifier {
                // Show app icon
                if let iconData = app.iconData,
                   let nsImage = NSImage(data: iconData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Fallback: app initial
                    Text(String(app.name.prefix(1)))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // Empty slot: plus button
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .buttonStyle(.plain)
        .help(slot.appIdentifier?.name ?? "Add app")
    }
}
