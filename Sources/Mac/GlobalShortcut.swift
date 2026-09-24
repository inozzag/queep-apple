import AppKit
import Carbon

@MainActor
final class MacDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProductAnalytics.start()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            let action = identifier.id
            Task { @MainActor in
                if action == 1 { MacCapture.shared.show() }
                else if action == 2 { MacCapture.shared.captureScreen() }
            }
            return noErr
        }, 1, &event, nil, &handler)
        for (id, key, label) in [(UInt32(1), kVK_Space, "⌘⇧Espaço"), (UInt32(2), kVK_ANSI_7, "⌘⇧7")] {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x51454550, id: id)
            let status = RegisterEventHotKey(UInt32(key), UInt32(cmdKey | shiftKey), identifier,
                                            GetApplicationEventTarget(), 0, &hotKey)
            if let hotKey, status == noErr { hotKeys.append(hotKey) }
            else { MacCapture.shared.shortcutIssues.append("Atalho \(label) indisponível. Use o menu.") }
        }
        MacCapture.shared.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MacCapture.shared.showLibrary() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
