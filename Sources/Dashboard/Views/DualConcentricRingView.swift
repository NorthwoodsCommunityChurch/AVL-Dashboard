import SwiftUI

/// A dual concentric ring view for GPU metrics.
/// Outer ring shows usage %, inner ring shows temperature.
struct DualConcentricRingView: View {
    let outerValue: Double
    let outerMaxValue: Double
    let outerColor: Color
    let innerValue: Double
    let innerMaxValue: Double
    let innerColor: Color
    let label: String
    let subtitle: String
    let isOnline: Bool

    var outerLineWidth: CGFloat = 3.5
    var innerLineWidth: CGFloat = 2.5
    var gap: CGFloat = 2
    var fontSize: CGFloat = 8

    private var outerProgress: Double {
        guard outerValue >= 0 else { return 0 }
        return min(outerValue / outerMaxValue, 1.0)
    }

    private var innerProgress: Double {
        guard innerValue >= 0 else { return 0 }
        return min(innerValue / innerMaxValue, 1.0)
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                // Outer ring background
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: outerLineWidth)

                // Outer ring progress (usage)
                Circle()
                    .trim(from: 0, to: isOnline ? outerProgress : 1)
                    .stroke(
                        isOnline ? outerColor : .red.opacity(0.6),
                        style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: outerProgress)

                // Inner ring background
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: innerLineWidth)
                    .padding(outerLineWidth / 2 + gap + innerLineWidth / 2)

                // Inner ring progress (temperature)
                Circle()
                    .trim(from: 0, to: isOnline ? innerProgress : 1)
                    .stroke(
                        isOnline ? innerColor : .red.opacity(0.4),
                        style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round)
                    )
                    .padding(outerLineWidth / 2 + gap + innerLineWidth / 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: innerProgress)

                // Center label (temperature value)
                Text(isOnline ? label : "--")
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isOnline ? Color.primary : Color.red.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            // GPU name below the ring
            Text(isOnline ? subtitle : "---")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
