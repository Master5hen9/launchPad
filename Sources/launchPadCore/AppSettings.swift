import AppKit
import Foundation

/// Persisted user preferences. Uses a dedicated defaults suite so settings
/// survive even when the app runs as a bare executable without an Info.plist.
public enum AppSettings {
    // UserDefaults is thread-safe in practice but not Sendable-annotated.
    nonisolated(unsafe) public static let defaultsStore =
        UserDefaults(suiteName: "com.ming.launchpad") ?? .standard

    public static var isPinchGestureEnabled: Bool {
        get { defaultsStore.object(forKey: "pinchGestureEnabled") as? Bool ?? true }
        set { defaultsStore.set(newValue, forKey: "pinchGestureEnabled") }
    }

    /// Whether the first-launch onboarding guide has been seen (and dismissed
    /// or completed), so it does not pop up on every launch.
    public static var hasCompletedOnboarding: Bool {
        get { defaultsStore.object(forKey: "hasCompletedOnboarding") as? Bool ?? false }
        set { defaultsStore.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Global hotkey

    public static var isGlobalHotkeyEnabled: Bool {
        get { defaultsStore.object(forKey: "globalHotkeyEnabled") as? Bool ?? true }
        set { defaultsStore.set(newValue, forKey: "globalHotkeyEnabled") }
    }

    /// Virtual key code of the shortcut; defaults to Space (49).
    public static var globalHotkeyKeyCode: Int {
        get { defaultsStore.object(forKey: "globalHotkeyKeyCode") as? Int ?? 49 }
        set { defaultsStore.set(newValue, forKey: "globalHotkeyKeyCode") }
    }

    /// `NSEvent.ModifierFlags.rawValue`; defaults to ⌘⇧ (Space).
    public static var globalHotkeyModifiers: UInt {
        get {
            defaultsStore.object(forKey: "globalHotkeyModifiers") as? UInt
                ?? NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        }
        set { defaultsStore.set(newValue, forKey: "globalHotkeyModifiers") }
    }

    /// Human-readable key name captured at record time (e.g. "空格").
    public static var globalHotkeyLabel: String {
        get { defaultsStore.string(forKey: "globalHotkeyLabel") ?? "空格" }
        set { defaultsStore.set(newValue, forKey: "globalHotkeyLabel") }
    }
}
