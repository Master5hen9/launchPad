import Foundation

/// Public bridge for managing hidden apps from outside the Launchpad UI
/// (e.g. the Settings window, which lives in a different module).
public enum HiddenAppsStore {
    public struct HiddenApp: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let path: String
    }

    /// Returns the currently hidden apps, resolved against a fresh app scan so
    /// names and paths stay current.
    public static func hiddenApps() -> [HiddenApp] {
        let layout = AppLayoutStore.load() ?? AppLayout()
        let apps = AppScanner.scan()
        let map = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        return layout.hiddenAppIDs.compactMap { id in
            guard let app = map[id] else { return nil }
            return HiddenApp(id: app.id, name: app.name, path: app.url.path)
        }
    }

    /// Restores a hidden app to the end of the Launchpad grid.
    public static func restore(appID: String) {
        guard var layout = AppLayoutStore.load() else { return }
        layout = AppLayout.unhide(appID: appID, in: layout)
        AppLayoutStore.save(layout)
    }
}
