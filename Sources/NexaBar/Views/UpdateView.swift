import SwiftUI
import AppKit

struct UpdateView: View {
    @ObservedObject var updateManager: UpdateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            header

            if let release = updateManager.availableRelease {
                patchNotesSection(release: release)

                progressOrActionSection(release: release)
            } else {
                Text("No update details available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 404)
        .background(NexaBackground())
        .tint(NexaTheme.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(NexaTheme.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(NexaTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("A fresh NexaBar")
                    .font(.headline)

                if let release = updateManager.availableRelease {
                    HStack(spacing: 6) {
                        Text("v\(release.version)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NexaTheme.accent)

                        Text("•  Current: v\(updateManager.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func patchNotesSection(release: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("What’s new", systemImage: "doc.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if release.dmgSize > 0 {
                    Text(ByteFormatter.bytes(Int64(release.dmgSize)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(release.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12, design: .default))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(10)
            }
            .frame(maxHeight: 180)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func progressOrActionSection(release: UpdateInfo) -> some View {
        switch updateManager.status {
        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("Downloading update... \(Int((progress * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        updateManager.cancelDownload()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
            .padding(.top, 4)

        case .installing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing update and restarting NexaBar...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)

        default:
            if let error = updateManager.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("View on GitHub") {
                    NSWorkspace.shared.open(release.htmlUrl)
                }
                .buttonStyle(NexaButtonStyle())

                Spacer()

                Button("Later") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)

                Button {
                    updateManager.downloadAndInstallUpdate(release: release)
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .buttonStyle(NexaButtonStyle(prominent: true))
            }
            .padding(.top, 4)
        }
    }
}
