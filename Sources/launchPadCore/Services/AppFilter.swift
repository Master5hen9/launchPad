import Foundation

/// Pure search filtering logic, kept separate from the UI so it is easy to test.
enum AppFilter {
    static func filter(_ apps: [AppRecord], query: String) -> [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
