import AppKit
import Carbon.HIToolbox
import Foundation

/// Registers a Carbon global hotkey so the Launchpad can be toggled from any
/// app without requiring Accessibility/Input Monitoring permission.
///
/// Carbon delivers hotkey callbacks on the application's main event loop;
/// registration state is guarded by a lock so the C callback can safely read
/// the trigger closure.
public final class GlobalHotkeyManager: @unchecked Sendable {
    public static let shared = GlobalHotkeyManager()

    private let lock = NSLock()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (@Sendable () -> Void)?

    private static let hotKeySignature: OSType = 0x4C50444B // "LPDK"

    /// Registers (or re-registers) the hotkey. Returns false when the combo is
    /// invalid or already claimed by another application.
    @discardableResult
    public func register(
        keyCode: UInt32,
        modifiers: UInt32,
        onTrigger: @escaping @Sendable () -> Void
    ) -> Bool {
        unregister()

        lock.lock()
        self.onTrigger = onTrigger
        lock.unlock()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.dispatchTrigger()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handler
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        var hotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            if let handler {
                RemoveEventHandler(handler)
            }
            return false
        }

        lock.lock()
        self.hotKeyRef = hotKey
        self.eventHandlerRef = handler
        lock.unlock()
        return true
    }

    public func unregister() {
        lock.lock()
        let hotKey = hotKeyRef
        let handler = eventHandlerRef
        hotKeyRef = nil
        eventHandlerRef = nil
        onTrigger = nil
        lock.unlock()

        if let handler {
            RemoveEventHandler(handler)
        }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
    }

    /// Converts an `NSEvent.ModifierFlags` raw value into Carbon modifiers.
    public static func carbonModifiers(from rawFlags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    private func dispatchTrigger() {
        lock.lock()
        let trigger = onTrigger
        lock.unlock()
        trigger?()
    }
}
