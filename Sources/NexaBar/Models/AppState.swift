import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var cpuPercent: Double = 0
    @Published var memoryPercent: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var diskPercent: Double = 0
    @Published var diskUsedGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var cpuTemperature: Double?
    @Published var downloadBytesPerSecond: Double = 0
    @Published var uploadBytesPerSecond: Double = 0
    @Published var audioDevices: [AudioDeviceItem] = []
    @Published var appAudioItems: [AppAudioItem] = []
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var toastMessage: String?
    @Published var statusVersion: Int = 0

    var onRequestClosePopover: (() -> Void)?
    var onRequestTogglePopover: (() -> Void)?

    let clipboard = ClipboardManager()
    private let monitor = SystemMonitor()
    private let audio = AudioController()
    private let appAudio = AppAudioController()
    private let screenshot = ScreenshotController()
    private let hotkey = HotKeyManager.shared
    private let worker = DispatchQueue(label: "com.nexabar.monitor", qos: .utility)
    private var monitorTimer: Timer?
    private var clipboardTimer: Timer?
    private var volumeTimer: Timer?
    private var toastTask: Task<Void, Never>?

    var menuBarText: String {
        let mode = UserDefaults.standard.string(forKey: "menuBarMode") ?? "balanced"
        let cpu = Int(cpuPercent.rounded())
        let mem = Int(memoryPercent.rounded())
        let disk = Int(diskPercent.rounded())
        let tempInt = cpuTemperature.map { Int($0.rounded()) }

        let cpuStr = String(format: "%2d%%", cpu)
        let memStr = String(format: "%2d%%", mem)
        let diskStr = String(format: "%2d%%", disk)
        let tempStr = tempInt.map { String(format: "%2d°", $0) } ?? "--°"
        let down = ByteFormatter.rate(downloadBytesPerSecond)
        let up = ByteFormatter.rate(uploadBytesPerSecond)

        switch mode {
        case "compact":
            return "\(cpuStr)  \(tempStr)"
        case "full":
            return "CPU \(cpuStr)  MEM \(memStr)  SSD \(diskStr)  \(tempStr)  ↓\(down) ↑\(up)"
        default:
            return "\(cpuStr)  \(memStr)  \(diskStr)  \(tempStr)  ↓\(down)"
        }
    }

    func start() {
        clipboardItems = clipboard.items
        refreshMonitor()
        refreshAudio()

        // Register Global Hotkey Cmd+Shift+V
        hotkey.onTrigger = { [weak self] in
            self?.onRequestTogglePopover?()
        }
        hotkey.registerDefaultShortcut()

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshMonitor() }
        }
        monitorTimer?.tolerance = 0.25

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshClipboard() }
        }
        clipboardTimer?.tolerance = 0.15

        volumeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAudio() }
        }
        volumeTimer?.tolerance = 0.5
    }

    func stop() {
        monitorTimer?.invalidate()
        clipboardTimer?.invalidate()
        volumeTimer?.invalidate()
        monitorTimer = nil
        clipboardTimer = nil
        volumeTimer = nil
        hotkey.unregister()
        appAudio.stop()
    }

    func refreshMonitor() {
        let monitor = self.monitor
        worker.async { [weak self, monitor] in
            let snapshot = monitor.snapshot()
            Task { @MainActor [weak self] in
                self?.cpuPercent = snapshot.cpuPercent
                self?.memoryPercent = snapshot.memoryPercent
                self?.memoryUsedGB = snapshot.memoryUsedGB
                self?.memoryTotalGB = snapshot.memoryTotalGB
                self?.diskPercent = snapshot.diskPercent
                self?.diskUsedGB = snapshot.diskUsedGB
                self?.diskTotalGB = snapshot.diskTotalGB
                self?.cpuTemperature = snapshot.cpuTemperature
                self?.downloadBytesPerSecond = snapshot.downloadBytesPerSecond
                self?.uploadBytesPerSecond = snapshot.uploadBytesPerSecond
                self?.statusVersion &+= 1
            }
        }
    }

    func refreshClipboard(force: Bool = false) {
        if clipboard.poll(force: force) {
            clipboardItems = clipboard.items
        }
    }

    func copyClipboardItem(_ item: ClipboardItem) {
        clipboard.copy(item)
        showToast(item.type == .image ? "Image Copied" : "Copied")
    }

    func deleteClipboardItem(_ item: ClipboardItem) {
        clipboard.delete(item)
        clipboardItems = clipboard.items
    }

    func clearClipboardHistory() {
        clipboard.clear()
        clipboardItems = []
        showToast("Clipboard history cleared")
    }

    func refreshAudio() {
        let audio = self.audio
        let appAudio = self.appAudio
        let currentAppItems = self.appAudioItems
        Task.detached(priority: .utility) { [weak self] in
            let devices = audio.getOutputDevices()
            let apps = appAudio.getRunningAudioApps(existingItems: currentAppItems)
            appAudio.synchronize(apps: apps)
            Task { @MainActor [weak self] in
                self?.audioDevices = devices
                self?.appAudioItems = apps
            }
        }
    }

    func setDeviceVolume(device: AudioDeviceItem, volume: Double) {
        if let index = audioDevices.firstIndex(where: { $0.id == device.id }) {
            audioDevices[index].volume = volume
        }
        let audio = self.audio
        Task.detached(priority: .userInitiated) {
            audio.setDeviceVolume(deviceID: device.id, volume: volume)
        }
    }

    func toggleDeviceMute(device: AudioDeviceItem) {
        if let index = audioDevices.firstIndex(where: { $0.id == device.id }) {
            audioDevices[index].isMuted.toggle()
        }
        let audio = self.audio
        Task.detached(priority: .userInitiated) {
            audio.toggleDeviceMute(deviceID: device.id, currentMute: !device.isMuted)
        }
    }

    func setDefaultAudioOutput(device: AudioDeviceItem) {
        for i in 0..<audioDevices.count {
            audioDevices[i].isDefaultOutput = (audioDevices[i].id == device.id)
        }
        let audio = self.audio
        Task.detached(priority: .userInitiated) { [weak self] in
            audio.setDefaultOutputDevice(id: device.id)
            let updated = audio.getOutputDevices()
            Task { @MainActor [weak self] in
                self?.audioDevices = updated
                self?.showToast("Audio output: \(device.name)")
            }
        }
    }

    func setAppVolume(app: AppAudioItem, volume: Double) {
        guard let index = appAudioItems.firstIndex(where: { $0.id == app.id }) else { return }
        appAudioItems[index].volume = volume
        let updatedApp = appAudioItems[index]

        appAudio.setAppVolume(app: updatedApp, volume: volume) { [weak self] errorMessage in
            guard let errorMessage else { return }
            Task { @MainActor [weak self] in
                self?.showToast(errorMessage)
            }
        }
    }

    func toggleAppMute(app: AppAudioItem) {
        guard let index = appAudioItems.firstIndex(where: { $0.id == app.id }) else { return }
        appAudioItems[index].isMuted.toggle()
        let updatedApp = appAudioItems[index]

        appAudio.setAppMute(app: updatedApp, isMuted: updatedApp.isMuted) { [weak self] errorMessage in
            guard let errorMessage else { return }
            Task { @MainActor [weak self] in
                self?.showToast(errorMessage)
            }
        }
    }

    func captureSelection() {
        onRequestClosePopover?()
        showToast("Select an area to capture")

        let screenshot = self.screenshot
        Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            let success = screenshot.captureSelectionToClipboard()
            try? await Task.sleep(for: .milliseconds(150))
            Task { @MainActor [weak self] in
                self?.refreshClipboard(force: true)
                self?.showToast(success ? "Screenshot copied to clipboard" : "Capture cancelled")
            }
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }
}
