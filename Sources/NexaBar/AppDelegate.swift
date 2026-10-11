import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let clipboardPopover = NSPopover()
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
        configureClipboardPopover()
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
        button.image = nil
        button.imagePosition = .noImage
        refreshStatusItem()
        button.toolTip = state.menuBarToolTip
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @MainActor private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: NexaTheme.panelWidth, height: NexaTheme.panelHeight)
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
            if event.keyCode == 53 { // Escape
                if self?.clipboardPopover.isShown == true {
                    self?.clipboardPopover.performClose(nil)
                    return nil
                }
                if self?.popover.isShown == true {
                    self?.popover.performClose(nil)
                    return nil
                }
            }
            return event
        }
    }

    @MainActor private func configureClipboardPopover() {
        clipboardPopover.behavior = .transient
        clipboardPopover.animates = true
        clipboardPopover.contentSize = NSSize(width: 380, height: 490)
        clipboardPopover.contentViewController = NSHostingController(
            rootView: StandaloneClipboardView(onSelect: { [weak self] in
                self?.clipboardPopover.performClose(nil)
            })
            .environmentObject(state)
        )

        state.onRequestCloseClipboard = { [weak self] in
            self?.clipboardPopover.performClose(nil)
        }

        state.onRequestToggleClipboard = { [weak self] in
            self?.toggleClipboardPopover(nil)
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

    private var lastMenuBarSummary: String = ""

    @MainActor private func refreshStatusItem() {
        guard let button = statusItem.button else { return }

        let summary = state.menuBarSummaryText
        guard summary != lastMenuBarSummary else { return }
        lastMenuBarSummary = summary

        statusItem.length = NSStatusItem.variableLength
        button.attributedTitle = state.menuBarAttributedString
        button.toolTip = state.menuBarToolTip
    }


    @MainActor @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showQuickMenu()
            return
        }

        if clipboardPopover.isShown {
            clipboardPopover.performClose(nil)
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor @objc private func toggleClipboardPopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        }

        if clipboardPopover.isShown {
            clipboardPopover.performClose(sender)
        } else {
            state.refreshClipboard(force: true)
            clipboardPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            clipboardPopover.contentViewController?.view.window?.makeKey()
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

        addItem("Open NexaBar", action: #selector(openPopoverFromMenu))
        addItem("Clipboard History (⌘⇧V)", action: #selector(openClipboardFromMenu))
        menu.addItem(.separator())
        addItem("Capture Selection → Clipboard", action: #selector(captureSelection))
        addItem("Open Activity Monitor", action: #selector(openActivityMonitor))
        addItem("Check for Updates...", action: #selector(checkForUpdatesFromMenu))
        menu.addItem(.separator())
        addItem("Quit NexaBar", action: #selector(quitApp), key: "q")

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @MainActor @objc private func openClipboardFromMenu() {
        toggleClipboardPopover(nil)
    }

    @MainActor @objc private func checkForUpdatesFromMenu() {
        state.updateManager.checkForUpdates(isUserInitiated: true)
        openPopoverFromMenu()
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
