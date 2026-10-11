import SwiftUI

struct RingGauge: View {
    let title: String
    let systemImage: String
    let value: Double
    let detail: String
    var accent: Color = NexaTheme.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percentage: Double { value.isFinite ? min(max(value, 0), 100) : 0 }
    private var tint: Color {
        if percentage >= 90 { return .red }
        if percentage >= 75 { return NexaTheme.amber }
        return accent
    }
    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().stroke(accent.opacity(0.11), lineWidth: 4)
                Circle().trim(from: 0, to: percentage / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: percentage)
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text("\(Int(percentage.rounded()))%")
                        .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                }
            }.frame(width: 70, height: 70)
            Text(title).font(.system(size: 11, weight: .medium))
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityValue("\(Int(percentage.rounded())) percent. \(detail)")
    }
}
