import Foundation

/// Records the last launch time per app id so the grid can be sorted by
/// "recently used". Persisted in the same defaults suite as other settings.
enum RecentlyUsedStore {
    private static let storageKey = "recentlyUsed"

    private static var dates: [String: Date] {
        get {
            guard let data = AppSettings.defaultsStore.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            AppSettings.defaultsStore.set(data, forKey: storageKey)
        }
    }

    static func recordLaunch(appID: String) {
        var values = dates
        values[appID] = Date()
        dates = values
    }

    static func lastLaunched(appID: String) -> Date? {
        dates[appID]
    }
}
