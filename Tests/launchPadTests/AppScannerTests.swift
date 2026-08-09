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
}
