import Foundation
import Testing
@testable import launchPadCore

struct AppCategoryTests {
    private func record(path: String) -> AppRecord {
        AppRecord(
            bundleIdentifier: nil,
            name: (path as NSString).lastPathComponent,
            url: URL(fileURLWithPath: path)
        )
    }

    @Test func testAllCategoryMatchesEverything() {
        let paths = [
            "/System/Applications/App Store.app",
            "/Applications/Safari.app",
            "/Users/ming/Applications/Helper.app",
            "/opt/homebrew/Caskroom/arc/1.0/Arc.app"
        ]
        for path in paths {
            #expect(AppCategory.all.contains(record(path: path)))
        }
    }

    @Test func testSystemCategoryOnlyMatchesSystemPaths() {
        #expect(AppCategory.system.contains(record(path: "/System/Applications/App Store.app")))
        #expect(AppCategory.system.contains(record(path: "/System/Library/CoreServices/Finder.app")))
        #expect(!AppCategory.system.contains(record(path: "/Applications/Safari.app")))
        #expect(!AppCategory.system.contains(record(path: "/opt/homebrew/Caskroom/arc/1.0/Arc.app")))
    }

    @Test func testUserCategoryMatchesApplicationsFolders() {
        #expect(AppCategory.user.contains(record(path: "/Applications/Safari.app")))
        #expect(AppCategory.user.contains(record(path: "/Users/ming/Applications/Helper.app")))
        #expect(!AppCategory.user.contains(record(path: "/System/Applications/App Store.app")))
        #expect(!AppCategory.user.contains(record(path: "/opt/homebrew/Caskroom/arc/1.0/Arc.app")))
    }

    @Test func testHomebrewCategoryMatchesCaskroomAndCellar() {
        #expect(AppCategory.homebrew.contains(record(path: "/opt/homebrew/Caskroom/arc/1.0/Arc.app")))
        #expect(AppCategory.homebrew.contains(record(path: "/usr/local/Cellar/python/3.11/Frameworks/Python.app")))
        #expect(!AppCategory.homebrew.contains(record(path: "/Applications/Safari.app")))
    }
}
