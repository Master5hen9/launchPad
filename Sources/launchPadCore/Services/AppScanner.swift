import Foundation

/// Scans well-known application directories for `.app` bundles.
enum AppScanner {
    /// Directories searched in priority order; the first copy of an app wins.
    static let searchDirectories: [URL] = {
        var directories = [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        directories.append(userApplications)
        return directories
    }()

    static func scan() -> [AppRecord] {
        var records: [AppRecord] = []
        var seenIdentifiers = Set<String>()
        var seenPaths = Set<String>()

        for directory in searchDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app", let bundle = Bundle(url: url) else {
                    continue
                }
                guard let record = makeRecord(bundle: bundle, url: url) else {
                    continue
                }

                if let bundleIdentifier = record.bundleIdentifier {
                    if seenIdentifiers.contains(bundleIdentifier) {
                        continue
                    }
                    seenIdentifiers.insert(bundleIdentifier)
                } else if seenPaths.contains(record.url.path) {
                    continue
                }
                seenPaths.insert(record.url.path)
                records.append(record)
            }
        }

        return records.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Builds a record from a bundle, preferring the display name over the
    /// bundle name over the file name.
    static func makeRecord(bundle: Bundle, url: URL) -> AppRecord? {
        let name = displayName(for: bundle, url: url)
        return AppRecord(bundleIdentifier: bundle.bundleIdentifier, name: name, url: url)
    }

    static func displayName(for bundle: Bundle, url: URL) -> String {
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
