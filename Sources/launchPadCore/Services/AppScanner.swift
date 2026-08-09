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
        directories.append(contentsOf: homebrewAppDirectories())
        return directories
    }()

    static func scan(in directories: [URL] = searchDirectories) -> [AppRecord] {
        var records: [AppRecord] = []
        var seenIdentifiers = Set<String>()
        var seenPaths = Set<String>()

        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                // Homebrew trees are `<root>/<name>/<version>/<App>.app`; never
                // descend deeper than that (keeps Cellar scans fast).
                if enumerator.level >= 3 {
                    enumerator.skipDescendants()
                }
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
            nameSortChineseFirst($0.name, $1.name)
        }
    }

    /// Orders names containing CJK characters before others, then falls back to
    /// the system locale's comparison (so Chinese apps lead the grid).
    static func nameSortChineseFirst(_ a: String, _ b: String) -> Bool {
        let aChinese = containsCJKCharacters(a)
        let bChinese = containsCJKCharacters(b)
        if aChinese != bChinese {
            return aChinese
        }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    private static func containsCJKCharacters(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)  // CJK Ext A
                || (0x4E00...0x9FFF).contains(scalar.value)  // CJK Unified
        }
    }

    /// Homebrew installs casks into `<prefix>/Caskroom/<cask>/<version>/<App>.app`
    /// and some formulae ship `.app` bundles in `<prefix>/Cellar/...`. Apps are
    /// normally symlinked/copied into /Applications, but not always, so scan
    /// both trees directly (deduplicated by bundle id in `scan(in:)`).
    static func homebrewAppDirectories(
        prefixes: [String] = ["/opt/homebrew", "/usr/local"]
    ) -> [URL] {
        prefixes
            .flatMap { prefix in
                ["Caskroom", "Cellar"].map { subdirectory in
                    URL(fileURLWithPath: "\(prefix)/\(subdirectory)", isDirectory: true)
                }
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Builds a record from a bundle, preferring the display name over the
    /// bundle name over the file name.
    static func makeRecord(bundle: Bundle, url: URL) -> AppRecord? {
        let name = displayName(for: bundle, url: url)
        return AppRecord(bundleIdentifier: bundle.bundleIdentifier, name: name, url: url)
    }

    static func displayName(
        for bundle: Bundle,
        url: URL,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        // Localized names first: when running as a bare executable,
        // `Bundle.object(forInfoDictionaryKey:)` falls back to English even on
        // Chinese systems, so match the system languages explicitly.
        if let localizedDisplayName = localizedString(
            forKey: "CFBundleDisplayName",
            in: bundle,
            url: url,
            preferredLanguages: preferredLanguages
        ) {
            return localizedDisplayName
        }
        if let localizedName = localizedString(
            forKey: "CFBundleName",
            in: bundle,
            url: url,
            preferredLanguages: preferredLanguages
        ) {
            return localizedName
        }
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

    /// Reads `InfoPlist.strings` from the app's localizations that best match
    /// the given preferred languages, e.g. the "微信" name WeChat ships in its
    /// `zh-Hans.lproj` while the Info.plist itself says "WeChat".
    private static func localizedString(
        forKey key: String,
        in bundle: Bundle,
        url: URL,
        preferredLanguages: [String]
    ) -> String? {
        let localizations = availableLocalizations(for: bundle, url: url)
        let preferred = Bundle.preferredLocalizations(
            from: localizations,
            forPreferences: preferredLanguages
        )
        for localization in preferred {
            // Old-style bundles sometimes use `zh_CN.lproj` folder names.
            for folderName in [localization, localization.replacingOccurrences(of: "-", with: "_")] {
                let stringsURL = url
                    .appendingPathComponent("Contents/Resources/\(folderName).lproj/InfoPlist.strings")
                guard let strings = NSDictionary(contentsOf: stringsURL),
                      let value = strings[key] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                return value
            }
        }
        return nil
    }

    private static func availableLocalizations(for bundle: Bundle, url: URL) -> [String] {
        let resourcesURL = url.appendingPathComponent("Contents/Resources")
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: resourcesURL.path))?
            .filter { $0.hasSuffix(".lproj") }
            .map { $0.dropLast(".lproj".count).replacingOccurrences(of: "_", with: "-") }
            .sorted() ?? []
        return listed.isEmpty ? bundle.localizations : listed
    }
}
