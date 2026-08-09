import Foundation

/// Pure search filtering logic, kept separate from the UI so it is easy to test.
enum AppFilter {
    static func filter(_ apps: [AppRecord], query: String) -> [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return apps
        }
        let needle = trimmed.lowercased()
        return apps.filter {
            if $0.name.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            return Pinyin.components(of: $0.name).contains { variant in
                variant.full.contains(needle) || variant.initials.contains(needle)
            }
        }
    }
}
