import SwiftUI
import AppKit

struct ClipboardPanel: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""

    private var filteredItems: [ClipboardItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(state.clipboardItems.prefix(10)) }
        return state.clipboardItems.filter { item in
            if item.type == .text, let text = item.text {
                return text.localizedCaseInsensitiveContains(query)
            } else if item.type == .image {
                return "image media screenshot".contains(query.lowercased())
            }
            return false
        }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Clipboard History", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                if !state.clipboardItems.isEmpty {
                    Button("Clear History") { state.clearClipboardHistory() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search clipboard…", text: $search)
                .textFieldStyle(.roundedBorder)

            if filteredItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("Copy text or images to build your history.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Images retained for 8+ hours • ⌘⇧V to toggle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 14)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        clipboardCard(for: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func clipboardCard(for item: ClipboardItem) -> some View {
        if item.type == .image {
            imageCard(for: item)
        } else {
            textCard(for: item)
        }
    }

    private func textCard(for item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Button {
                state.copyClipboardItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text((item.text ?? "").replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12.5))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                state.deleteClipboardItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func imageCard(for item: ClipboardItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Image Thumbnail
            if let imageURL = state.clipboard.getImageURL(for: item),
               let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 68)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }

            // Image Metadata
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Copied media")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(item.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text("Image history retained for 8+ hours")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 2)

                HStack(spacing: 16) {
                    if let size = item.fileSize {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Size")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    if let w = item.width, let h = item.height {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Resolution")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(w)x\(h)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Spacer()

                    Button {
                        state.copyClipboardItem(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        state.deleteClipboardItem(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
