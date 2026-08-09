import Foundation

/// Persists the user's Launchpad arrangement (grid order + folders) as JSON in
/// the same preferences suite as the other settings.
enum AppLayoutStore {
    private static let storageKey = "appLayout"

    static func load() -> AppLayout? {
        guard let data = AppSettings.defaultsStore.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppLayout.self, from: data)
    }

    static func save(_ layout: AppLayout) {
        guard let data = try? JSONEncoder().encode(layout) else {
            return
        }
        AppSettings.defaultsStore.set(data, forKey: storageKey)
    }
}
