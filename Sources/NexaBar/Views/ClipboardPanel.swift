import SwiftUI
import AppKit

struct ClipboardPanel: View {
    var body: some View { NexaClipboardBrowser(scrolls: false) }
}

private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all = "All", text = "Text", images = "Images"
    var id: String { rawValue }
}

struct NexaClipboardBrowser: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @State private var filter: ClipboardFilter = .all
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool
    var scrolls = false
    var focusOnAppear = false
    var onCopy: (() -> Void)?

    private var filteredItems: [ClipboardItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.clipboardItems.filter { item in
            let matchesType = filter == .all || (filter == .text && item.type == .text) || (filter == .images && item.type == .image)
            guard matchesType else { return false }
            guard !query.isEmpty else { return true }
            if item.type == .text { return item.text?.localizedCaseInsensitiveContains(query) ?? false }
            return "image media screenshot photo".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            controls
            if scrolls {
                ScrollView { itemList.padding(.bottom, 10) }.scrollIndicators(.hidden)
            } else { itemList }
        }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear history", role: .destructive) { state.clearClipboardHistory() }
        } message: { Text("Saved text and images will be removed from NexaBar.") }
        .onAppear { if focusOnAppear { searchFocused = true } }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your recent copies").font(.system(size: 12, weight: .medium))
                Spacer()
                if !state.clipboardItems.isEmpty {
                    Button("Clear all") { confirmClear = true }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Find something you copied…", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                    .onSubmit { if let first = filteredItems.first { copy(first) } }
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
                }
            }
            .padding(11).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            HStack(spacing: 6) {
                ForEach(ClipboardFilter.allCases) { choice in
                    Button { filter = choice } label: {
                        Text(choice.rawValue).font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .foregroundStyle(filter == choice ? NexaTheme.accent : Color.secondary)
                            .background(filter == choice ? NexaTheme.accent.opacity(0.12) : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(filter == choice ? .isSelected : [])
                }
                Spacer()
                Text("\(filteredItems.count) items").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var itemList: some View {
        LazyVStack(spacing: 8) {
            if filteredItems.isEmpty {
                NexaEmptyState(symbol: "doc.on.clipboard", title: state.clipboardItems.isEmpty ? "Your next idea starts here" : "Nothing found",
                               detail: state.clipboardItems.isEmpty ? "Copy text or an image on your Mac.\nWe'll keep it here for your next step." : "Try another search or switch the filter.")
                    .nexaCard()
            } else {
                ForEach(filteredItems) { item in
                    NexaClipboardRow(item: item, onCopy: { copy(item) }, onDelete: { state.deleteClipboardItem(item) })
                }
            }
        }
    }

    private func copy(_ item: ClipboardItem) {
        state.copyClipboardItem(item)
        onCopy?()
    }
}

private struct NexaClipboardRow: View {
    @EnvironmentObject private var state: AppState
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onCopy) {
                HStack(alignment: .center, spacing: 10) {
                    if item.type == .image {
                        NexaClipboardThumbnail(url: state.clipboard.getImageURL(for: item))
                    } else {
                        Image(systemName: "text.alignleft").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NexaTheme.accent).frame(width: 36, height: 36)
                            .background(NexaTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        if item.type == .image {
                            Text("Copied image").font(.system(size: 12, weight: .medium))
                            Text(imageDetail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text((item.text ?? "").replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Text(item.createdAt, style: .relative).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Copy to clipboard")
            Button(action: onCopy) { Image(systemName: "doc.on.doc").foregroundStyle(NexaTheme.accent) }
                .buttonStyle(NexaIconButtonStyle()).help("Copy item").accessibilityLabel("Copy item")
            Button(action: onDelete) { Image(systemName: "trash").font(.system(size: 10.5)).foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Delete item").accessibilityLabel("Delete item")
        }.padding(12).nexaCard()
    }

    private var imageDetail: String {
        var parts: [String] = []
        if let width = item.width, let height = item.height { parts.append("\(width) × \(height)") }
        if let size = item.fileSize { parts.append(size) }
        return parts.joined(separator: " · ")
    }
}

private struct NexaClipboardThumbnail: View {
    let url: URL?
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 42, height: 42)
        .background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { image = url.flatMap { NSImage(contentsOf: $0) } }
    }
}
