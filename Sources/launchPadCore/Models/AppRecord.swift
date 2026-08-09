import Foundation

/// A single installed application shown in the Launchpad grid.
struct AppRecord: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String?
    let name: String
    let url: URL

    var id: String {
        bundleIdentifier ?? url.path
    }
}
