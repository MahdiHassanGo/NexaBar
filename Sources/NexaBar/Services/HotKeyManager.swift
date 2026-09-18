import Carbon
import AppKit

final class HotKeyManager: @unchecked Sendable {
    static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (@MainActor () -> Void)?

    init() {}

    func registerDefaultShortcut() {
        // Key Code 9 is 'v', cmdKey + shiftKey
        register(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4E584252) // "NXBR"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerProc: EventHandlerUPP = { _, event, userData in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.onTrigger?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), handlerProc, 1, &eventType, selfPtr, &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
