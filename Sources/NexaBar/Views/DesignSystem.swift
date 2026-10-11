import SwiftUI
import AppKit

enum NexaTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0.69, green: 0.63, blue: 0.96, alpha: 1)
        }
        return NSColor(srgbRed: 0.46, green: 0.39, blue: 0.81, alpha: 1)
    })
    static let actionFill = Color(red: 0.46, green: 0.39, blue: 0.81)
    static let mint = Color(red: 0.27, green: 0.64, blue: 0.55)
    static let amber = Color(red: 0.84, green: 0.59, blue: 0.31)
    static let panelWidth: CGFloat = 404
    static let panelHeight: CGFloat = 610

    static func colorScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct NexaBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
            LinearGradient(
                colors: [NexaTheme.accent.opacity(scheme == .dark ? 0.09 : 0.055), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .accessibilityHidden(true)
    }
}

private struct NexaCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.55 : 0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.7)
            )
    }
}

extension View {
    func nexaCard() -> some View { modifier(NexaCardModifier()) }
}

struct NexaSectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
                .tracking(1.4).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(.horizontal, 2)
    }
}

struct NexaButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(prominent ? NexaTheme.actionFill : Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct NexaIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .frame(width: 29, height: 29)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.045), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct NexaEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .foregroundStyle(NexaTheme.accent).frame(width: 52, height: 52)
                .background(NexaTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 17))
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
    }
}
