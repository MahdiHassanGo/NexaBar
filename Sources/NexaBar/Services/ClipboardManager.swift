import AppKit
import Foundation

enum ClipboardType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardType
    let text: String?
    let imageFileName: String?
    let width: Int?
    let height: Int?
    let fileSize: String?
    let createdAt: Date

    init(text: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.type = .text
        self.text = text
        self.imageFileName = nil
        self.width = nil
        self.height = nil
        self.fileSize = nil
        self.createdAt = createdAt
    }

    init(imageFileName: String, width: Int, height: Int, fileSize: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.type = .image
        self.text = nil
        self.imageFileName = imageFileName
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.createdAt = createdAt
    }
}

final class ClipboardManager: @unchecked Sendable {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private(set) var items: [ClipboardItem] = []
    private let storageKey = "clipboardHistory"
    private let maximumItems = 50
    private let retentionHours: Double = 8.0 // Keep image history for at least 8 hours

    let imagesDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        imagesDirectory = home.appendingPathComponent(".nexabar/clipboard_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        lastChangeCount = pasteboard.changeCount
        load()
        purgeExpiredItems()
    }

    @discardableResult
    func poll(force: Bool = false) -> Bool {
        let changeCount = pasteboard.changeCount
        guard force || changeCount != lastChangeCount else { return false }
        lastChangeCount = changeCount

        // 1. Try reading Image from Pasteboard (direct NSImage or file URL)
        if let objects = pasteboard.readObjects(forClasses: [NSImage.self, NSURL.self], options: nil) {
            for obj in objects {
                let imageToUse: NSImage?
                if let img = obj as? NSImage {
                    imageToUse = img
                } else if let url = obj as? URL, ["png", "jpg", "jpeg", "tiff", "heic", "webp"].contains(url.pathExtension.lowercased()) {
                    imageToUse = NSImage(contentsOf: url)
                } else {
                    imageToUse = nil
                }

                if let image = imageToUse,
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {

                    let width = Int(bitmap.pixelsWide)
                    let height = Int(bitmap.pixelsHigh)

                    let sizeFormatted = ByteFormatter.bytes(Int64(pngData.count))
                    let fileName = "\(UUID().uuidString).png"
                    let fileURL = imagesDirectory.appendingPathComponent(fileName)

                    do {
                        try pngData.write(to: fileURL)
                        let newItem = ClipboardItem(
                            imageFileName: fileName,
                            width: width,
                            height: height,
                            fileSize: sizeFormatted
                        )
                        items.insert(newItem, at: 0)
                        trimAndSave()
                        return true
                    } catch {
                        // Ignore error saving image
                    }
                }
            }
        }

        // 2. Try reading Text from Pasteboard
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            if items.first?.text == text { return false }
            items.removeAll { $0.text == text }
            items.insert(ClipboardItem(text: text), at: 0)
            trimAndSave()
            return true
        }

        return false
    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        if item.type == .image, let fileName = item.imageFileName {
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: fileURL) {
                pasteboard.writeObjects([image])
            }
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func delete(_ item: ClipboardItem) {
        if item.type == .image, let fileName = item.imageFileName {
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        for item in items {
            if item.type == .image, let fileName = item.imageFileName {
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll()
        save()
    }

    func getImageURL(for item: ClipboardItem) -> URL? {
        guard item.type == .image, let fileName = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    private func purgeExpiredItems() {
        let cutoff = Date().addingTimeInterval(-retentionHours * 3600)
        let expired = items.filter { $0.createdAt < cutoff }
        for item in expired {
            if item.type == .image, let fileName = item.imageFileName {
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { $0.createdAt < cutoff }
        save()
    }

    private func trimAndSave() {
        if items.count > maximumItems {
            let overflow = items.suffix(from: maximumItems)
            for item in overflow {
                if item.type == .image, let fileName = item.imageFileName {
                    let fileURL = imagesDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            items = Array(items.prefix(maximumItems))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        items = Array(decoded.prefix(maximumItems))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
