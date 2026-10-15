import Foundation
import AppKit
import Combine

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let publishedAt: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
        case assets
    }
}

struct SemanticVersion: Comparable, Equatable {
    let components: [Int]
    let raw: String

    init(_ string: String) {
        self.raw = string
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let mainPart = cleaned.components(separatedBy: CharacterSet(charactersIn: "-+")).first ?? cleaned
        let numbers = mainPart.split(separator: ".").compactMap { part in
            Int(part.filter { $0.isNumber })
        }
        self.components = numbers.isEmpty ? [0] : numbers
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left != right {
                return false
            }
        }
        return true
    }
}

struct UpdateInfo: Identifiable, Equatable {
    var id: String { version }
    let version: String
    let title: String
    let body: String
    let htmlUrl: URL
    let dmgUrl: URL?
    let dmgSize: Int
    let publishedDate: String?
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(release: UpdateInfo)
    case downloading(progress: Double)
    case installing
    case failed(error: String)
}

@MainActor
final class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateManager()

    @Published var status: UpdateStatus = .idle
    @Published var isChecking: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var availableRelease: UpdateInfo? = nil
    @Published var lastCheckDate: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var showUpdateSheet: Bool = false

    private let repoOwner = "MahdiHassanGo"
    private let repoName = "NexaBar"
    private var downloadTask: URLSessionDownloadTask?
    private var checkTimer: Timer?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var currentVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        return "3.4.0"
    }

    var isAutoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    override init() {
        super.init()
    }

    func start() {
        guard isAutoCheckEnabled else { return }

        // Initial background check 4 seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.checkForUpdates(isUserInitiated: false)
        }

        // Periodic check every 4 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: 14400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.isAutoCheckEnabled == true else { return }
                self?.checkForUpdates(isUserInitiated: false)
            }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        downloadTask?.cancel()
    }

    func checkForUpdates(isUserInitiated: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        status = .checking
        errorMessage = nil

        let endpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=50"
        guard let url = URL(string: endpoint) else {
            isChecking = false
            status = .idle
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NexaBar-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.isChecking = false
                    self.status = .failed(error: "Could not connect to update server.")
                    if isUserInitiated {
                        self.errorMessage = "Could not check for updates."
                    }
                    return
                }

                let releases: [GitHubRelease]
                if let decodedArray = try? JSONDecoder().decode([GitHubRelease].self, from: data) {
                    releases = decodedArray
                } else if let singleRelease = try? JSONDecoder().decode(GitHubRelease.self, from: data) {
                    releases = [singleRelease]
                } else {
                    throw URLError(.cannotParseResponse)
                }

                // Filter out draft releases
                let candidateReleases = releases.filter { !($0.draft ?? false) }

                // Find the absolute highest/newest version among all published releases.
                // This skips intermediate releases (e.g. going directly from v3.0 to v5.6).
                guard let newestRelease = candidateReleases.max(by: { SemanticVersion($0.tagName) < SemanticVersion($1.tagName) }) else {
                    self.isChecking = false
                    self.availableRelease = nil
                    self.status = .upToDate(version: self.currentVersion)
                    self.showUpdateSheet = false
                    return
                }

                let remoteSemVer = SemanticVersion(newestRelease.tagName)
                let currentSemVer = SemanticVersion(self.currentVersion)

                let dmgAsset = newestRelease.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                let dmgUrl = dmgAsset.flatMap { URL(string: $0.browserDownloadUrl) }
                let dmgSize = dmgAsset?.size ?? 0

                let updateInfo = UpdateInfo(
                    version: newestRelease.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                    title: newestRelease.name ?? "NexaBar \(newestRelease.tagName)",
                    body: newestRelease.body ?? "No release notes provided.",
                    htmlUrl: URL(string: newestRelease.htmlUrl) ?? url,
                    dmgUrl: dmgUrl,
                    dmgSize: dmgSize,
                    publishedDate: newestRelease.publishedAt
                )

                self.isChecking = false
                self.lastCheckDate = Date()

                if remoteSemVer > currentSemVer {
                    // Strictly newer release available: directly target the newest release
                    self.availableRelease = updateInfo
                    self.status = .updateAvailable(release: updateInfo)
                    if isUserInitiated {
                        self.showUpdateSheet = true
                    }
                } else {
                    // Already up to date: do not show any update notices or banners
                    self.availableRelease = nil
                    self.status = .upToDate(version: self.currentVersion)
                    self.showUpdateSheet = false
                }
            } catch {
                self.isChecking = false
                self.status = .failed(error: error.localizedDescription)
                if isUserInitiated {
                    self.errorMessage = "Update check failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func downloadAndInstallUpdate(release: UpdateInfo) {
        guard let dmgUrl = release.dmgUrl else {
            // If no DMG attached, open browser release page
            NSWorkspace.shared.open(release.htmlUrl)
            return
        }

        status = .downloading(progress: 0.0)
        downloadProgress = 0.0
        errorMessage = nil

        var request = URLRequest(url: dmgUrl)
        request.setValue("NexaBar-App", forHTTPHeaderField: "User-Agent")
        downloadTask = downloadSession.downloadTask(with: request)
        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let rel = availableRelease {
            status = .updateAvailable(release: rel)
        } else {
            status = .idle
        }
    }

    // MARK: - URLSessionDownloadDelegate
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        Task { @MainActor in
            self.downloadProgress = min(max(progress, 0.0), 1.0)
            self.status = .downloading(progress: self.downloadProgress)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.status = .failed(error: error.localizedDescription)
            self.errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("NexaBar-Update.dmg")

        try? FileManager.default.removeItem(at: destinationURL)
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            Task { @MainActor in
                self.performInstall(dmgURL: destinationURL)
            }
        } catch {
            Task { @MainActor in
                self.status = .failed(error: "Failed to save downloaded installer: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func performInstall(dmgURL: URL) {
        status = .installing

        let bundleURL = Bundle.main.bundleURL
        let currentAppPath = bundleURL.path
        let isAppBundle = bundleURL.pathExtension == "app" && !currentAppPath.contains("/.build/")

        guard isAppBundle else {
            // Running in developer / terminal mode; open DMG in Finder
            NSWorkspace.shared.open(dmgURL)
            status = .idle
            showUpdateSheet = false
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let dmgPath = dmgURL.path
        let targetPath = currentAppPath

        let script = """
        #!/bin/bash
        exec > /tmp/nexabar_updater.log 2>&1
        PID=\(pid)
        DMG_PATH="\(dmgPath)"
        TARGET_APP="\(targetPath)"
        MOUNT_DIR="/tmp/nexabar_mount_$$"

        echo "Updating NexaBar from $DMG_PATH to $TARGET_APP (PID: $PID)..."

        # 1. Terminate old process gracefully, then forcefully if still alive
        kill -15 "$PID" 2>/dev/null
        for i in {1..20}; do
            if ! kill -0 "$PID" 2>/dev/null; then
                echo "Process $PID exited."
                break
            fi
            sleep 0.1
        done
        kill -9 "$PID" 2>/dev/null

        # 2. Mount DMG
        mkdir -p "$MOUNT_DIR"
        hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" 2>/dev/null

        # 3. Copy new app bundle
        SOURCE_APP="$MOUNT_DIR/NexaBar.app"
        if [ -d "$SOURCE_APP" ]; then
            echo "Replacing $TARGET_APP..."
            rm -rf "$TARGET_APP" 2>/dev/null
            cp -R "$SOURCE_APP" "$TARGET_APP" 2>/dev/null
            xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
        fi

        # 4. Detach and cleanup
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
        rm -f "$DMG_PATH" 2>/dev/null

        # 5. Relaunch new NexaBar
        sleep 0.3
        echo "Launching $TARGET_APP..."
        open "$TARGET_APP"
        echo "Update finished!"
        """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("nexabar_updater.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()

            // Close UI immediately and exit cleanly so AppKit cannot block termination
            NSApp.windows.forEach { $0.orderOut(nil) }
            exit(0)
        } catch {
            // Fallback: reveal DMG in Finder
            NSWorkspace.shared.open(dmgURL)
            status = .failed(error: "Auto-install failed: \(error.localizedDescription)")
        }
    }
}
