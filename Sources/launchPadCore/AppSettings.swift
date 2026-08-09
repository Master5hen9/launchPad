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
}
