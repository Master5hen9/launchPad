import Foundation

/// Process-wide cache of the scanned app list, so opening the Launchpad never
/// re-runs a full directory scan (which would show the loading screen every
/// time). Warmed at launch and refreshed whenever the app directories change.
@MainActor
public enum AppCatalog {
    private static var records: [AppRecord]?
    private static var refreshTask: Task<[AppRecord], Never>?

    /// The last scanned app list, or nil before the first scan completes.
    public static var current: [AppRecord]? { records }

    /// Returns the cached list, scanning (coalesced) only when needed.
    public static func loadIfNeeded() async -> [AppRecord] {
        if let records {
            return records
        }
        return await refresh()
    }

    /// Re-scans the app directories. Concurrent refreshes share one scan.
    public static func refresh() async -> [AppRecord] {
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task.detached(priority: .userInitiated) {
            AppScanner.scan()
        }
        refreshTask = task
        let result = await task.value
        records = result
        refreshTask = nil
        return result
    }
}
