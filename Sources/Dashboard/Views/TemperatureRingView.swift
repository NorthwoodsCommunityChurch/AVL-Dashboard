import SwiftUI
import Shared

/// A compact ring view for displaying a metric value as a circular progress indicator.
struct MetricRingView: View {
    let value: Double
    let maxValue: Double
    let color: Color
    let label: String
    let icon: String
    let isOnline: Bool
    var lineWidth: CGFloat = 3.5
    var fontSize: CGFloat = 9

    private var progress: Double {
        guard value >= 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: isOnline ? progress : 1)
                    .stroke(
                        isOnline ? color : .red.opacity(0.6),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                Image(systemName: isOnline ? icon : "xmark")
                    .font(.system(size: fontSize, weight: isOnline ? .regular : .bold))
                    .foregroundStyle(isOnline ? color : .red)
            }

            Text(isOnline ? label : "---")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(isOnline ? Color.primary : Color.red.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Convenience: Temperature ring with threshold-based coloring.
struct TemperatureRingView: View {
    let temperature: Double
    let thresholds: MachineThresholds
    let isOnline: Bool
    var ringLineWidth: CGFloat = 3.5
    var fontSize: CGFloat = 9

    private var ringColor: Color {
        guard temperature >= 0 else { return .gray }
        if temperature >= thresholds.critical { return .red }
        if temperature >= thresholds.warning { return .orange }
        if temperature >= thresholds.good { return .yellow }
        return .green
    }

    var body: some View {
        MetricRingView(
            value: temperature,
            maxValue: 120,
            color: ringColor,
            label: temperature >= 0 ? "\(Int(temperature))°C" : "--",
            icon: "thermometer.medium",
            isOnline: isOnline,
            lineWidth: ringLineWidth,
            fontSize: fontSize
        )
    }
}
