import AppKit
import Carbon

extension Notification.Name {
    static let queepQuickCapture = Notification.Name("Queep.quickCapture")
}

@MainActor
final class MacDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .queepQuickCapture, object: nil)
            }
            return noErr
        }, 1, &event, nil, &handler)
        let identifier = EventHotKeyID(signature: 0x51454550, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), identifier,
                                        GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            NSLog("Queep: global shortcut unavailable (%d). Menu capture remains available.", status)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
