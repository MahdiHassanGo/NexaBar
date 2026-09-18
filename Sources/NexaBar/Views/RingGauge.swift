import SwiftUI

struct RingGauge: View {
    let title: String
    let systemImage: String
    let value: Double
    let detail: String

    private var normalized: Double { min(max(value / 100, 0), 1) }

    private var tint: Color {
        switch value {
        case 90...: return .red
        case 75...: return .orange
        default: return .accentColor
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.16), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: normalized)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: normalized)

                VStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(Int(value.rounded()))%")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 72, height: 72)

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
