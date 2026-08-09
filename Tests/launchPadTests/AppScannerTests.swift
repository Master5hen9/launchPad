import Foundation
import Testing
@testable import launchPadCore

struct AppScannerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFakeApp(
        in directory: URL,
        named fileName: String,
        info: [String: String]
    ) throws -> URL {
        let appURL = directory.appendingPathComponent("\(fileName).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": "com.example.\(fileName)"
        ]
        for (key, value) in info {
            plist[key] = value
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }

    private func addLocalizedStrings(
        _ values: [String: String],
        localization: String,
        to appURL: URL
    ) throws {
        let lprojURL = appURL
            .appendingPathComponent("Contents/Resources/\(localization).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lprojURL, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        try data.write(to: lprojURL.appendingPathComponent("InfoPlist.strings"))
    }

    @Test func displayNamePrefersCFBundleDisplayName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "Sample", info: [
            "CFBundleDisplayName": "Sample App",
            "CFBundleName": "Sample"
        ])
        let bundle = try #require(Bundle(url: url))

        #expect(AppScanner.displayName(for: bundle, url: url) == "Sample App")
    }

    @Test func displayNamePrefersSystemLocalizedName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "WeChat", info: [
            "CFBundleDisplayName": "WeChat",
            "CFBundleName": "WeChat"
        ])
        try addLocalizedStrings(
            ["CFBundleDisplayName": "微信", "CFBundleName": "微信"],
            localization: "zh-Hans",
            to: url
        )
        let bundle = try #require(Bundle(url: url))

        #expect(
            AppScanner.displayName(
                for: bundle,
                url: url,
                preferredLanguages: ["zh-Hans-CN", "en-CN"]
            ) == "微信"
        )
    }

    @Test func displayNamePrefersLocalizedBundleNameOverEnglishDisplayName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "WeChat", info: [
            "CFBundleDisplayName": "WeChat",
            "CFBundleName": "WeChat"
        ])
        try addLocalizedStrings(
            ["CFBundleName": "微信"],
            localization: "zh-Hans",
            to: url
        )
        let bundle = try #require(Bundle(url: url))

        #expect(
            AppScanner.displayName(
                for: bundle,
                url: url,
                preferredLanguages: ["zh-Hans-CN"]
            ) == "微信"
        )
    }

    @Test func displayNameFallsBackToPlistWhenNoLocalizationExists() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "Sample", info: [
            "CFBundleDisplayName": "Sample App"
        ])
        let bundle = try #require(Bundle(url: url))

        #expect(
            AppScanner.displayName(
                for: bundle,
                url: url,
                preferredLanguages: ["zh-Hans-CN"]
            ) == "Sample App"
        )
    }

    @Test func displayNameFallsBackToFileName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "Sample", info: [:])
        let bundle = try #require(Bundle(url: url))

        #expect(AppScanner.displayName(for: bundle, url: url) == "Sample")
    }

    @Test func makeRecordUsesBundleIdentifierAsID() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try makeFakeApp(in: directory, named: "Sample", info: [:])
        let bundle = try #require(Bundle(url: url))
        let record = try #require(AppScanner.makeRecord(bundle: bundle, url: url))

        #expect(record.bundleIdentifier == "com.example.Sample")
        #expect(record.id == "com.example.Sample")
        #expect(record.url == url)
    }

    @Test func homebrewAppDirectoriesOnlyReturnsExistingDirectories() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Caskroom", isDirectory: true),
            withIntermediateDirectories: true
        )

        let dirs = AppScanner.homebrewAppDirectories(prefixes: [directory.path])
        #expect(dirs.map(\.lastPathComponent) == ["Caskroom"])
    }

    @Test func scanFindsAppsNestedInHomebrewCellarStyleTrees() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let versionDirectory = directory
            .appendingPathComponent("Cellar/python@3.14/3.14.0_1", isDirectory: true)
        try FileManager.default.createDirectory(
            at: versionDirectory,
            withIntermediateDirectories: true
        )
        _ = try makeFakeApp(in: versionDirectory, named: "IDLE 3", info: [
            "CFBundleDisplayName": "IDLE 3",
            "CFBundleIdentifier": "org.python.IDLE"
        ])
        _ = try makeFakeApp(in: versionDirectory, named: "Python Launcher 3", info: [
            "CFBundleDisplayName": "Python Launcher 3",
            "CFBundleIdentifier": "org.python.PythonLauncher"
        ])

        let records = AppScanner.scan(in: [directory.appendingPathComponent("Cellar", isDirectory: true)])

        #expect(records.map(\.name).sorted() == ["IDLE 3", "Python Launcher 3"])
    }

    @Test func scanDeduplicatesAppsAcrossDirectories() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try makeFakeApp(in: directory, named: "Sample", info: [
            "CFBundleDisplayName": "Sample App",
            "CFBundleIdentifier": "com.example.Sample"
        ])
        let cellarDirectory = directory.appendingPathComponent("Cellar", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cellarDirectory.appendingPathComponent("sample/1.0", isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = try makeFakeApp(
            in: cellarDirectory.appendingPathComponent("sample/1.0", isDirectory: true),
            named: "Sample",
            info: [
                "CFBundleDisplayName": "Sample App",
                "CFBundleIdentifier": "com.example.Sample"
            ]
        )

        let records = AppScanner.scan(in: [directory, cellarDirectory])

        #expect(records.count == 1)
        #expect(records.first?.url.lastPathComponent == "Sample.app")
        #expect(records.first?.url.path.contains("/Cellar/") == false)
    }

    @Test func scanSkipsDanglingSymlinks() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let versionDirectory = directory
            .appendingPathComponent("Caskroom/mos/3.5.0", isDirectory: true)
        try FileManager.default.createDirectory(
            at: versionDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: versionDirectory.appendingPathComponent("Mos.app", isDirectory: true),
            withDestinationURL: URL(fileURLWithPath: "/nonexistent/Mos.app")
        )

        let records = AppScanner.scan(in: [directory.appendingPathComponent("Caskroom", isDirectory: true)])

        #expect(records.isEmpty)
    }
}
