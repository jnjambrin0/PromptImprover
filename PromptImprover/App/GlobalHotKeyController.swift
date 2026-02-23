import AppKit
import Carbon.HIToolbox

final class GlobalHotKeyController {
    private let hotKeySignature: OSType = 0x50494D48 // "PIMH"
    private let hotKeyIdentifier: UInt32 = 1
    private let keyCodeI: UInt32 = UInt32(kVK_ANSI_I)
    private let modifiers: UInt32 = UInt32(cmdKey) | UInt32(optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    var onHotKeyPressed: (() -> Void)?

    func register() {
        guard hotKeyRef == nil, eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            Logging.debug(
                "Failed installing global hotkey handler for Cmd+Option+I (OSStatus: \(handlerStatus))."
            )
            eventHandlerRef = nil
            return
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        let registerStatus = RegisterEventHotKey(
            keyCodeI,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            Logging.debug(
                "Failed registering global hotkey Cmd+Option+I (OSStatus: \(registerStatus))."
            )
            unregister()
            return
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event else {
            return
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return
        }
        guard hotKeyID.signature == hotKeySignature, hotKeyID.id == hotKeyIdentifier else {
            return
        }

        onHotKeyPressed?()
    }

    fileprivate func dispatchHotKeyEvent(_ event: EventRef?) {
        handleHotKeyEvent(event)
    }
}

private let globalHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
        return noErr
    }

    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.dispatchHotKeyEvent(event)
    return noErr
}
