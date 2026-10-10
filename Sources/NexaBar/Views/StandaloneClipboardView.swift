import SwiftUI
import AppKit

struct StandaloneClipboardView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool

    var onSelect: (() -> Void)?

    private var filteredItems: [ClipboardItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.clipboardItems }
        return state.clipboardItems.filter { item in
            if item.type == .text, let text = item.text {
                return text.localizedCaseInsensitiveContains(query)
            } else if item.type == .image {
                return "image media screenshot photo".contains(query.lowercased())
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.3)

            searchBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider().opacity(0.3)

            itemsList

            Divider().opacity(0.3)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 380, height: 490)
        .background(.ultraThinMaterial)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Clipboard History", systemImage: "doc.on.clipboard.fill")
                .font(.system(size: 13, weight: .bold))

            Text("\(state.clipboardItems.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)

            Spacer()

            if !state.clipboardItems.isEmpty {
                Button {
                    state.clearClipboardHistory()
                } label: {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                onSelect?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search copied text & images…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = filteredItems.first {
                        copyAndClose(first)
                    }
                }

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
        )
    }

    private var itemsList: some View {
        ScrollView {
            if filteredItems.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 50)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(filteredItems) { item in
                        itemRow(for: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func itemRow(for item: ClipboardItem) -> some View {
        if item.type == .image {
            imageRow(for: item)
        } else {
            textRow(for: item)
        }
    }

    private func textRow(for item: ClipboardItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                copyAndClose(item)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text((item.text ?? "").replacingOccurrences(of: "\r\n", with: "\n"))
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        Text(item.createdAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                state.deleteClipboardItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .help("Delete from history")
        }
        .padding(9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    private func imageRow(for item: ClipboardItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                copyAndClose(item)
            } label: {
                HStack(spacing: 10) {
                    if let imageURL = state.clipboard.getImageURL(for: item),
                       let nsImage = NSImage(contentsOf: imageURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Copied image")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            if let w = item.width, let h = item.height {
                                Text("\(w)×\(h)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            if let size = item.fileSize {
                                Text(size)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.createdAt, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                state.deleteClipboardItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete from history")
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(search.isEmpty ? "No clipboard history yet" : "No matches found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(search.isEmpty ? "Items you copy on your Mac will appear here." : "Try searching for something else.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            Text("↵ to copy top result • Esc to dismiss")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Spacer()

            Text("⌘⇧V")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
        }
    }

    private func copyAndClose(_ item: ClipboardItem) {
        state.copyClipboardItem(item)
        onSelect?()
    }
}
