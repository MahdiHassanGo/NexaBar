import SwiftUI

struct StandaloneClipboardView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("nexaAppearance") private var appearance = "system"
    var onSelect: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(NexaTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(NexaTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clipboard").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Pick up where you left off.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onSelect?() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(NexaIconButtonStyle()).help("Close (Esc)").accessibilityLabel("Close clipboard")
            }.padding(18)
            NexaClipboardBrowser(scrolls: true, focusOnAppear: true, onCopy: onSelect)
                .padding(.horizontal, 16)
            HStack {
                Text("Return to copy · Esc to close").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("⌘⇧V").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 380, height: 490).background(NexaBackground()).tint(NexaTheme.accent)
        .preferredColorScheme(NexaTheme.colorScheme(for: appearance))
    }
}
