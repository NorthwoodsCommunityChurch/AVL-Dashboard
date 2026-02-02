import SwiftUI

struct OnlineIndicatorView: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isOnline ? "Online" : "Offline")
                .font(.caption2)
                .foregroundStyle(isOnline ? .primary : .secondary)
        }
    }
}
