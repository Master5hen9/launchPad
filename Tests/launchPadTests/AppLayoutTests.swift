import Foundation
import Testing
@testable import launchPadCore

struct AppLayoutTests {
    private func app(_ identifier: String, _ name: String) -> AppRecord {
        AppRecord(
            bundleIdentifier: identifier,
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    private var alpha: AppRecord { app("com.example.Alpha", "Alpha") }
    private var beta: AppRecord { app("com.example.Beta", "Beta") }
    private var gamma: AppRecord { app("com.example.Gamma", "Gamma") }

    @Test func reconcileAppendsNewAppsAlphabetically() {
        let saved = AppLayout(
            entries: [.app("com.example.Beta")],
            folders: [:],
            hasCustomOrder: true
        )
        let layout = AppLayout.reconcile(saved, with: [beta, alpha, gamma])

        #expect(layout.entries == [
            .app("com.example.Beta"),
            .app("com.example.Alpha"),
            .app("com.example.Gamma")
        ])
    }

    @Test func reconcileDropsStaleAppsAndEmptyFolders() {
        let emptyFolder = LaunchpadFolder(id: "f1", name: "空文件夹", appIDs: [])
        let staleFolder = LaunchpadFolder(id: "f2", name: "过期", appIDs: ["com.example.Gone"])
        let saved = AppLayout(
            entries: [.app("com.example.Gone"), .folder("f1"), .folder("f2"), .app("com.example.Alpha")],
            folders: ["f1": emptyFolder, "f2": staleFolder]
        )

        let layout = AppLayout.reconcile(saved, with: [alpha])

        #expect(layout.entries == [.app("com.example.Alpha")])
        #expect(layout.folders.isEmpty)
    }

    @Test func reconcileKeepsFolderAppsOutOfGrid() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let saved = AppLayout(
            entries: [.folder("f1"), .app("com.example.Beta")],
            folders: ["f1": folder],
            hasCustomOrder: true
        )

        let layout = AppLayout.reconcile(saved, with: [alpha, beta, gamma])

        #expect(layout.entries == [.folder("f1"), .app("com.example.Beta"), .app("com.example.Gamma")])
        #expect(layout.folders["f1"]?.appIDs == ["com.example.Alpha"])
    }

    @Test func makeFolderMergesAppsAtTargetPosition() throws {
        let layout = AppLayout(
            entries: [.app("com.example.Alpha"), .app("com.example.Beta"), .app("com.example.Gamma")],
            folders: [:]
        )

        let merged = AppLayout.makeFolder(
            containing: ["com.example.Alpha", "com.example.Gamma"],
            named: "工具",
            at: "com.example.Gamma",
            in: layout
        )

        #expect(merged.entries.count == 2)
        #expect(merged.entries[0] == .app("com.example.Beta"))
        #expect(merged.folders.count == 1)
        let folder = try #require(merged.folders.values.first)
        #expect(folder.name == "工具")
        #expect(folder.appIDs == ["com.example.Alpha", "com.example.Gamma"])
    }

    @Test func makeFolderRequiresAtLeastTwoApps() {
        let layout = AppLayout(entries: [.app("com.example.Alpha")], folders: [:])
        let merged = AppLayout.makeFolder(
            containing: ["com.example.Alpha"],
            named: "工具",
            at: "com.example.Alpha",
            in: layout
        )
        #expect(merged == layout)
    }

    @Test func addAppToFolderRemovesItFromGridAndDeduplicates() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Beta")],
            folders: ["f1": folder]
        )

        let updated = AppLayout.add(appID: "com.example.Beta", toFolder: "f1", in: layout)
        #expect(updated.entries == [.folder("f1")])
        #expect(updated.folders["f1"]?.appIDs == ["com.example.Alpha", "com.example.Beta"])

        let again = AppLayout.add(appID: "com.example.Beta", toFolder: "f1", in: updated)
        #expect(again.folders["f1"]?.appIDs == ["com.example.Alpha", "com.example.Beta"])
    }

    @Test func moveAppWithinFolderReordersMembers() {
        let folder = LaunchpadFolder(
            id: "f1",
            name: "工具",
            appIDs: ["com.example.Alpha", "com.example.Beta", "com.example.Gamma"]
        )
        let layout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])

        let moved = AppLayout.move(
            appID: "com.example.Gamma",
            inFolder: "f1",
            before: "com.example.Alpha",
            in: layout
        )
        #expect(moved.folders["f1"]?.appIDs == [
            "com.example.Gamma",
            "com.example.Alpha",
            "com.example.Beta"
        ])

        let toEnd = AppLayout.move(
            appID: "com.example.Gamma",
            inFolder: "f1",
            before: nil,
            in: moved
        )
        #expect(toEnd.folders["f1"]?.appIDs == [
            "com.example.Alpha",
            "com.example.Beta",
            "com.example.Gamma"
        ])
    }

    @Test func moveAppWithinFolderIgnoresMissingOrSelfTargets() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let layout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])

        let selfTarget = AppLayout.move(
            appID: "com.example.Alpha",
            inFolder: "f1",
            before: "com.example.Alpha",
            in: layout
        )
        #expect(selfTarget == layout)

        let unknown = AppLayout.move(
            appID: "com.example.Gone",
            inFolder: "f1",
            before: "com.example.Beta",
            in: layout
        )
        #expect(unknown == layout)
    }

    @Test func moveEntryBeforeTargetAndToEnd() {
        let layout = AppLayout(
            entries: [.app("com.example.Alpha"), .app("com.example.Beta"), .app("com.example.Gamma")],
            folders: [:]
        )

        let moved = AppLayout.move(entryID: "app:com.example.Alpha", before: "app:com.example.Gamma", in: layout)
        #expect(moved.entries == [
            .app("com.example.Beta"),
            .app("com.example.Alpha"),
            .app("com.example.Gamma")
        ])

        let toEnd = AppLayout.move(entryID: "app:com.example.Alpha", before: nil, in: moved)
        #expect(toEnd.entries == [
            .app("com.example.Beta"),
            .app("com.example.Gamma"),
            .app("com.example.Alpha")
        ])

        let noop = AppLayout.move(entryID: "app:com.example.Alpha", before: "app:com.example.Alpha", in: layout)
        #expect(noop == layout)
    }

    @Test func removeAppFromFolderInsertsItAfterTheFolder() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Gamma")],
            folders: ["f1": folder]
        )

        let updated = AppLayout.remove(appID: "com.example.Alpha", fromFolder: "f1", in: layout)

        #expect(updated.folders["f1"]?.appIDs == ["com.example.Beta"])
        #expect(updated.entries == [
            .folder("f1"),
            .app("com.example.Alpha"),
            .app("com.example.Gamma")
        ])
    }

    @Test func removingLastAppDeletesTheFolder() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])

        let updated = AppLayout.remove(appID: "com.example.Alpha", fromFolder: "f1", in: layout)

        #expect(updated.folders.isEmpty)
        #expect(updated.entries == [.app("com.example.Alpha")])
    }

    @Test func deleteFolderReturnsAppsToTheGrid() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Gamma")],
            folders: ["f1": folder]
        )

        let updated = AppLayout.delete(folderID: "f1", in: layout)

        #expect(updated.folders.isEmpty)
        #expect(updated.entries == [
            .app("com.example.Gamma"),
            .app("com.example.Alpha"),
            .app("com.example.Beta")
        ])
    }

    @Test func hideAppRemovesItFromGridAndFolders() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Gamma")],
            folders: ["f1": folder]
        )

        let hidden = AppLayout.hide(appID: "com.example.Alpha", in: layout)

        #expect(hidden.hiddenAppIDs == ["com.example.Alpha"])
        #expect(hidden.entries == [.folder("f1"), .app("com.example.Gamma")])
        #expect(hidden.folders["f1"]?.appIDs == ["com.example.Beta"])

        let gridOnly = AppLayout(entries: [.app("com.example.Beta")], folders: [:])
        let hiddenGridOnly = AppLayout.hide(appID: "com.example.Beta", in: gridOnly)
        #expect(hiddenGridOnly.entries.isEmpty)
        #expect(hiddenGridOnly.hiddenAppIDs == ["com.example.Beta"])
    }

    @Test func hideLastFolderAppDeletesTheFolder() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])

        let hidden = AppLayout.hide(appID: "com.example.Alpha", in: layout)

        #expect(hidden.folders.isEmpty)
        #expect(hidden.entries.isEmpty)
        #expect(hidden.hiddenAppIDs == ["com.example.Alpha"])
    }

    @Test func unhideAppRestoresItAtTheEndOfTheGrid() {
        let layout = AppLayout(
            entries: [.app("com.example.Beta")],
            folders: [:],
            hiddenAppIDs: ["com.example.Alpha"]
        )

        let restored = AppLayout.unhide(appID: "com.example.Alpha", in: layout)

        #expect(restored.hiddenAppIDs.isEmpty)
        #expect(restored.entries == [.app("com.example.Beta"), .app("com.example.Alpha")])
    }

    @Test func reconcileKeepsHiddenAppsOutOfTheGrid() {
        let saved = AppLayout(
            entries: [.app("com.example.Beta")],
            folders: [:],
            hiddenAppIDs: ["com.example.Alpha"]
        )

        let layout = AppLayout.reconcile(saved, with: [alpha, beta, gamma])

        #expect(layout.hiddenAppIDs == ["com.example.Alpha"])
        #expect(layout.entries == [.app("com.example.Beta"), .app("com.example.Gamma")])
    }

    @Test func reconcilePrunesHiddenAppsThatNoLongerExist() {
        let saved = AppLayout(
            entries: [.app("com.example.Beta")],
            folders: [:],
            hiddenAppIDs: ["com.example.Gone"],
            hasCustomOrder: true
        )

        let layout = AppLayout.reconcile(saved, with: [alpha, beta])

        #expect(layout.hiddenAppIDs.isEmpty)
        #expect(layout.entries == [.app("com.example.Beta"), .app("com.example.Alpha")])
    }

    @Test func reconcileSortsChineseNamesFirstWhenNoCustomOrder() {
        let wechat = AppRecord(
            bundleIdentifier: "com.example.WeChat",
            name: "微信",
            url: URL(fileURLWithPath: "/Applications/WeChat.app")
        )
        let saved = AppLayout(
            entries: [.app("com.example.Beta"), .app("com.example.WeChat")],
            folders: [:]
        )

        let layout = AppLayout.reconcile(saved, with: [wechat, beta, alpha])

        #expect(layout.entries == [
            .app("com.example.WeChat"),
            .app("com.example.Alpha"),
            .app("com.example.Beta")
        ])
    }

    @Test func reconcilePreservesManualOrder() {
        let saved = AppLayout(
            entries: [.app("com.example.Beta"), .app("com.example.Alpha")],
            folders: [:],
            hasCustomOrder: true
        )

        let layout = AppLayout.reconcile(saved, with: [alpha, beta, gamma])

        #expect(layout.entries == [
            .app("com.example.Beta"),
            .app("com.example.Alpha"),
            .app("com.example.Gamma")
        ])
    }

    @Test func reorderMarksLayoutAsCustomized() {
        let layout = AppLayout(
            entries: [.app("com.example.Alpha"), .app("com.example.Beta")],
            folders: [:]
        )
        let moved = AppLayout.move(
            entryID: "app:com.example.Alpha",
            before: "app:com.example.Beta",
            in: layout
        )
        #expect(moved.hasCustomOrder == true)

        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let folderLayout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])
        let folderMoved = AppLayout.move(
            appID: "com.example.Beta",
            inFolder: "f1",
            before: "com.example.Alpha",
            in: folderLayout
        )
        #expect(folderMoved.hasCustomOrder == true)
    }

    @Test func removeDeletedAppClearsItEverywhere() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha", "com.example.Beta"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Gamma")],
            folders: ["f1": folder],
            hiddenAppIDs: ["com.example.Gamma"]
        )

        let removed = AppLayout.removeDeleted(appID: "com.example.Alpha", in: layout)
        #expect(removed.folders["f1"]?.appIDs == ["com.example.Beta"])
        #expect(removed.hiddenAppIDs == ["com.example.Gamma"])

        let removedHidden = AppLayout.removeDeleted(appID: "com.example.Gamma", in: removed)
        #expect(removedHidden.hiddenAppIDs.isEmpty)
        #expect(removedHidden.entries == [.folder("f1")])
    }

    @Test func renameFolderUpdatesName() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(entries: [.folder("f1")], folders: ["f1": folder])

        let renamed = AppLayout.rename(folderID: "f1", to: "效率", in: layout)

        #expect(renamed.folders["f1"]?.name == "效率")
    }

    @Test func resolvedItemsSkipsMissingEntries() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Beta"), .app("com.example.Gone")],
            folders: ["f1": folder]
        )

        let items = layout.resolvedItems(with: [alpha, beta, gamma])

        #expect(items.count == 2)
        #expect(items[0].id == "folder:f1")
        #expect(items[1].id == "app:com.example.Beta")
    }

    @Test func layoutCodableRoundTrip() {
        let folder = LaunchpadFolder(id: "f1", name: "工具", appIDs: ["com.example.Alpha"])
        let layout = AppLayout(
            entries: [.folder("f1"), .app("com.example.Beta")],
            folders: ["f1": folder],
            hiddenAppIDs: ["com.example.Gamma"]
        )

        let data = try? JSONEncoder().encode(layout)
        let decoded = try? JSONDecoder().decode(AppLayout.self, from: try #require(data))

        #expect(decoded == layout)
    }

    @Test func layoutDecodesWithoutHiddenAppsKey() throws {
        let json = #"{"entries":[{"app":{"_0":"com.example.Alpha"}}],"folders":{}}"#
        let data = try #require(json.data(using: .utf8))
        let layout = try JSONDecoder().decode(AppLayout.self, from: data)

        #expect(layout.hiddenAppIDs.isEmpty)
        #expect(layout.entries == [.app("com.example.Alpha")])
    }

    @Test func dragPayloadParses() {
        #expect(GridDragPayload.parse("app:com.example.Alpha")?.kind == .app)
        #expect(GridDragPayload.parse("app:com.example.Alpha")?.id == "com.example.Alpha")
        #expect(GridDragPayload.parse("folder:xyz")?.kind == .folder)
        #expect(GridDragPayload.parse("folder:xyz")?.id == "xyz")
        #expect(GridDragPayload.parse("unknown:xyz") == nil)
        #expect(GridDragPayload.parse("") == nil)
    }
}
