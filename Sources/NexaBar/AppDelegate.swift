import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 194)
    private let popover = NSPopover()
    private let state = AppState()
    private var cancellables = Set<AnyCancellable>()
    private var localEventMonitor: Any?

    @MainActor override init() {
        super.init()
    }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        if let iconURL, let logoImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = logoImage
        }
        configureStatusItem()
        configurePopover()
        configureObservers()
        state.start()
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        state.stop()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
    }

    @MainActor private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "NexaBar")
        button.imagePosition = .imageLeading
        refreshStatusItem()
        button.toolTip = "NexaBar (⌘⇧V to toggle)"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @MainActor private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 404, height: 610)
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(state)
        )

        state.onRequestClosePopover = { [weak self] in
            self?.popover.performClose(nil)
        }

        state.onRequestTogglePopover = { [weak self] in
            self?.togglePopover(nil)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53, self?.popover.isShown == true { // Escape
                self?.popover.performClose(nil)
                return nil
            }
            return event
        }
    }

    @MainActor private func configureObservers() {
        state.$statusVersion
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
    }

    @MainActor private func refreshStatusItem() {
        guard let button = statusItem.button else { return }

        // Keep a fixed width for each selected layout. NSStatusItem.variableLength causes
        // every changing network/CPU value to resize the item and shove neighboring icons.
        let mode = UserDefaults.standard.string(forKey: "menuBarMode") ?? "balanced"
        switch mode {
        case "compact": statusItem.length = 108
        case "full": statusItem.length = 300
        default: statusItem.length = 194
        }

        let text = " " + state.menuBarText
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
    }

    @MainActor @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showQuickMenu()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor private func showQuickMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        func addItem(_ title: String, action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }

        addItem("Open NexaBar (⌘⇧V)", action: #selector(openPopoverFromMenu))
        menu.addItem(.separator())
        addItem("Capture Selection → Clipboard", action: #selector(captureSelection))
        addItem("Open Activity Monitor", action: #selector(openActivityMonitor))
        menu.addItem(.separator())
        addItem("Quit NexaBar", action: #selector(quitApp), key: "q")

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @MainActor @objc private func openPopoverFromMenu() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc private func captureSelection() {
        state.captureSelection()
    }

    @MainActor @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    @MainActor @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
