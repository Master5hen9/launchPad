import Foundation

/// A single installed application shown in the Launchpad grid.
public struct AppRecord: Identifiable, Hashable, Sendable {
    public let bundleIdentifier: String?
    public let name: String
    public let url: URL

    public var id: String {
        bundleIdentifier ?? url.path
    }

    public init(bundleIdentifier: String?, name: String, url: URL) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.url = url
    }
}
