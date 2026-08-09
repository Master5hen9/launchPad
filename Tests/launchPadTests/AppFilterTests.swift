import Foundation
import Testing
@testable import launchPadCore

struct AppFilterTests {
    private let apps = [
        AppRecord(bundleIdentifier: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/System/Applications/Safari.app")),
        AppRecord(bundleIdentifier: "com.apple.Music", name: "音乐", url: URL(fileURLWithPath: "/System/Applications/Music.app")),
        AppRecord(bundleIdentifier: "com.apple.Mail", name: "Mail", url: URL(fileURLWithPath: "/System/Applications/Mail.app"))
    ]

    @Test func emptyQueryReturnsAllApps() {
        #expect(AppFilter.filter(apps, query: "").count == 3)
        #expect(AppFilter.filter(apps, query: "   ").count == 3)
    }

    @Test func filterMatchesNameCaseInsensitively() {
        #expect(AppFilter.filter(apps, query: "safari").map(\.name) == ["Safari"])
        #expect(AppFilter.filter(apps, query: "SAFARI").map(\.name) == ["Safari"])
    }

    @Test func filterMatchesNonLatinCharacters() {
        #expect(AppFilter.filter(apps, query: "音乐").map(\.name) == ["音乐"])
    }

    @Test func filterWithNoMatchesReturnsEmpty() {
        #expect(AppFilter.filter(apps, query: "不存在").isEmpty)
    }

    @Test func filterTrimsQueryWhitespace() {
        #expect(AppFilter.filter(apps, query: "  mail  ").map(\.name) == ["Mail"])
    }
}
