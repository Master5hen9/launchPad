import Foundation

/// A user-created folder of apps shown in the Launchpad grid.
struct LaunchpadFolder: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var appIDs: [String]
}

/// One entry in the Launchpad grid: either an app or a folder.
enum LaunchpadItem: Identifiable, Hashable, Sendable {
    case app(AppRecord)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let app):
            "app:\(app.id)"
        case .folder(let folder):
            "folder:\(folder.id)"
        }
    }

    var name: String {
        switch self {
        case .app(let app):
            app.name
        case .folder(let folder):
            folder.name
        }
    }

}

/// Reference to one grid entry in the persisted layout.
enum GridEntry: Codable, Hashable, Sendable {
    case app(String)
    case folder(String)
}

/// The persisted, user-defined Launchpad arrangement: grid order plus folders.
///
/// The layout only stores stable IDs (bundle identifier or path), so it keeps
/// working across app scans. Apps that were removed or renamed are pruned when
/// the layout is reconciled with a fresh scan.
struct AppLayout: Codable, Equatable, Sendable {
    var entries: [GridEntry] = []
    var folders: [String: LaunchpadFolder] = [:]
    /// Apps the user hid from the Launchpad grid; they stay out of the grid
    /// across scans until restored from Settings.
    var hiddenAppIDs: [String] = []
    /// True once the user manually reordered anything. While false, reconcile
    /// keeps the grid sorted with Chinese-named apps first.
    var hasCustomOrder = false
}

extension AppLayout {
    /// Layouts saved before hidden apps existed have no `hiddenAppIDs` key;
    /// fall back to an empty list so decoding never discards a user layout.
    private enum CodingKeys: String, CodingKey {
        case entries
        case folders
        case hiddenAppIDs
        case hasCustomOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([GridEntry].self, forKey: .entries)
        folders = try container.decode([String: LaunchpadFolder].self, forKey: .folders)
        hiddenAppIDs = try container.decodeIfPresent([String].self, forKey: .hiddenAppIDs) ?? []
        hasCustomOrder = try container.decodeIfPresent(Bool.self, forKey: .hasCustomOrder) ?? false
    }
}

/// Plain-text drag payload used by the grid's drag & drop, e.g. `app:com.x` or
/// `folder:<uuid>`. Stored as an item provider string so SwiftUI can transfer
/// it without any custom `Transferable` conformance.
struct GridDragPayload: Equatable {
    enum Kind: Equatable {
        case app
        case folder
    }

    let kind: Kind
    let id: String

    static func encode(kind: Kind, id: String) -> String {
        switch kind {
        case .app:
            "app:\(id)"
        case .folder:
            "folder:\(id)"
        }
    }

    static func parse(_ string: String) -> GridDragPayload? {
        if string.hasPrefix("app:") {
            return GridDragPayload(kind: .app, id: String(string.dropFirst(4)))
        }
        if string.hasPrefix("folder:") {
            return GridDragPayload(kind: .folder, id: String(string.dropFirst(7)))
        }
        return nil
    }
}

extension AppLayout {
    /// Merges a saved layout with a fresh app scan:
    /// - keeps the saved grid order and folders;
    /// - prunes apps that no longer exist and folders left empty;
    /// - appends newly installed apps (alphabetically) to the end of the grid.
    static func reconcile(_ saved: AppLayout?, with apps: [AppRecord]) -> AppLayout {
        let appMap = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var layout = saved ?? AppLayout()
        layout.hiddenAppIDs = layout.hiddenAppIDs.filter { appMap[$0] != nil }

        var folders: [String: LaunchpadFolder] = [:]
        for (id, folder) in layout.folders {
            let validIDs = folder.appIDs.filter {
                appMap[$0] != nil && !layout.hiddenAppIDs.contains($0)
            }
            guard !validIDs.isEmpty else { continue }
            var folder = folder
            folder.appIDs = validIDs
            folders[id] = folder
        }
        layout.folders = folders

        var entries: [GridEntry] = []
        var seen = Set<String>()
        var entryAppIDs = Set<String>()
        for entry in layout.entries {
            switch entry {
            case .app(let appID):
                let marker = "app:\(appID)"
                guard appMap[appID] != nil,
                      !layout.hiddenAppIDs.contains(appID),
                      !folders.values.contains(where: { $0.appIDs.contains(appID) }) else {
                    continue
                }
                guard seen.insert(marker).inserted else { continue }
                entries.append(entry)
                entryAppIDs.insert(appID)
            case .folder(let folderID):
                let marker = "folder:\(folderID)"
                guard folders[folderID] != nil, seen.insert(marker).inserted else { continue }
                entries.append(entry)
            }
        }
        layout.entries = entries

        let folderAppIDs = Set(folders.values.flatMap(\.appIDs))
        let remaining = apps
            .filter {
                !folderAppIDs.contains($0.id)
                    && !entryAppIDs.contains($0.id)
                    && !layout.hiddenAppIDs.contains($0.id)
            }
            .sorted { AppScanner.nameSortChineseFirst($0.name, $1.name) }
        for app in remaining {
            layout.entries.append(.app(app.id))
        }

        if !layout.hasCustomOrder {
            layout.entries.sort { a, b in
                let aName = entryName(a, appMap: appMap, folders: layout.folders)
                let bName = entryName(b, appMap: appMap, folders: layout.folders)
                return AppScanner.nameSortChineseFirst(aName, bName)
            }
        }
        return layout
    }

    private static func entryName(
        _ entry: GridEntry,
        appMap: [String: AppRecord],
        folders: [String: LaunchpadFolder]
    ) -> String {
        switch entry {
        case .app(let appID):
            appMap[appID]?.name ?? ""
        case .folder(let folderID):
            folders[folderID]?.name ?? ""
        }
    }

    /// Resolves the grid entries back into display items, skipping anything
    /// whose app or folder is no longer present.
    func resolvedItems(with apps: [AppRecord]) -> [LaunchpadItem] {
        let appMap = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        return entries.compactMap { entry in
            switch entry {
            case .app(let appID):
                appMap[appID].map(LaunchpadItem.app)
            case .folder(let folderID):
                folders[folderID].map(LaunchpadItem.folder)
            }
        }
    }

    /// Creates a folder from the given app IDs, removes those apps from the
    /// grid, and inserts the folder at `targetAppID`'s former position.
    static func makeFolder(
        containing appIDs: [String],
        named name: String,
        at targetAppID: String?,
        in layout: AppLayout
    ) -> AppLayout {
        let uniqueIDs = appIDs.reduce(into: [String]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        guard uniqueIDs.count > 1 else { return layout }

        let targetIndex = layout.entries.firstIndex { entry in
            guard case .app(let id) = entry else { return false }
            return id == targetAppID
        } ?? layout.entries.count

        var layout = layout
        let folderID = UUID().uuidString
        layout.folders[folderID] = LaunchpadFolder(id: folderID, name: name, appIDs: uniqueIDs)
        layout.entries.removeAll { entry in
            guard case .app(let id) = entry else { return false }
            return uniqueIDs.contains(id)
        }
        layout.entries.insert(.folder(folderID), at: min(targetIndex, layout.entries.count))
        layout.hasCustomOrder = true
        return layout
    }

    /// Adds an app to a folder (removing it from the grid) unless it is
    /// already a member.
    static func add(appID: String, toFolder folderID: String, in layout: AppLayout) -> AppLayout {
        guard var folder = layout.folders[folderID], !folder.appIDs.contains(appID) else {
            return layout
        }
        folder.appIDs.append(appID)
        var layout = layout
        layout.folders[folderID] = folder
        layout.entries.removeAll { entry in
            guard case .app(let id) = entry else { return false }
            return id == appID
        }
        layout.hasCustomOrder = true
        return layout
    }

    /// Moves a grid entry before `targetEntryID` (or to the end when nil).
    /// `entryID`/`targetEntryID` use `LaunchpadItem.id` form (`app:`/`folder:`).
    static func move(entryID: String, before targetEntryID: String?, in layout: AppLayout) -> AppLayout {
        guard let sourceIndex = layout.entries.firstIndex(where: { entryMatches(entryID, $0) }) else {
            return layout
        }
        if let targetEntryID, targetEntryID == entryID {
            return layout
        }

        var entries = layout.entries
        let entry = entries.remove(at: sourceIndex)
        if let targetEntryID,
           let targetIndex = entries.firstIndex(where: { entryMatches(targetEntryID, $0) }) {
            entries.insert(entry, at: targetIndex)
        } else {
            entries.append(entry)
        }
        var layout = layout
        layout.entries = entries
        layout.hasCustomOrder = true
        return layout
    }

    /// Moves an app within a folder, before `targetAppID` (or to the end when
    /// nil). Used for drag-and-drop sorting inside the folder screen.
    static func move(
        appID: String,
        inFolder folderID: String,
        before targetAppID: String?,
        in layout: AppLayout
    ) -> AppLayout {
        guard var folder = layout.folders[folderID],
              let sourceIndex = folder.appIDs.firstIndex(of: appID) else {
            return layout
        }
        if let targetAppID, targetAppID == appID {
            return layout
        }

        var appIDs = folder.appIDs
        let moved = appIDs.remove(at: sourceIndex)
        if let targetAppID,
           let targetIndex = appIDs.firstIndex(of: targetAppID) {
            appIDs.insert(moved, at: targetIndex)
        } else {
            appIDs.append(moved)
        }
        folder.appIDs = appIDs
        var layout = layout
        layout.folders[folderID] = folder
        layout.hasCustomOrder = true
        return layout
    }

    /// Removes an app from a folder; it returns to the grid right after the
    /// folder. An emptied folder is deleted.
    static func remove(appID: String, fromFolder folderID: String, in layout: AppLayout) -> AppLayout {
        guard var folder = layout.folders[folderID],
              let index = folder.appIDs.firstIndex(of: appID) else {
            return layout
        }
        folder.appIDs.remove(at: index)
        var layout = layout

        if folder.appIDs.isEmpty {
            layout.folders.removeValue(forKey: folderID)
            layout.entries.removeAll { entryMatches("folder:\(folderID)", $0) }
            layout.entries.append(.app(appID))
            layout.hasCustomOrder = true
            return layout
        }

        layout.folders[folderID] = folder
        if let folderIndex = layout.entries.firstIndex(where: { entryMatches("folder:\(folderID)", $0) }) {
            layout.entries.insert(.app(appID), at: folderIndex + 1)
        } else {
            layout.entries.append(.app(appID))
        }
        layout.hasCustomOrder = true
        return layout
    }

    static func rename(folderID: String, to name: String, in layout: AppLayout) -> AppLayout {
        guard var folder = layout.folders[folderID] else { return layout }
        folder.name = name
        var layout = layout
        layout.folders[folderID] = folder
        return layout
    }

    /// Hides an app: removes it from the grid and any folders (deleting
    /// folders left empty) and records it as hidden so later scans don't add
    /// it back. Reversible via `unhide(appID:in:)`.
    static func hide(appID: String, in layout: AppLayout) -> AppLayout {
        guard !layout.hiddenAppIDs.contains(appID) else { return layout }
        var layout = layout
        layout.hiddenAppIDs.append(appID)
        layout.entries.removeAll { entryMatches("app:\(appID)", $0) }
        removeFromFolders(appID: appID, in: &layout)
        return layout
    }

    /// Restores a hidden app to the end of the grid.
    static func unhide(appID: String, in layout: AppLayout) -> AppLayout {
        guard layout.hiddenAppIDs.contains(appID) else { return layout }
        var layout = layout
        layout.hiddenAppIDs.removeAll { $0 == appID }
        removeFromFolders(appID: appID, in: &layout)
        layout.entries.append(.app(appID))
        return layout
    }

    /// Removes a deleted app from the layout entirely: grid entries, folders,
    /// and the hidden list.
    static func removeDeleted(appID: String, in layout: AppLayout) -> AppLayout {
        var layout = layout
        layout.hiddenAppIDs.removeAll { $0 == appID }
        layout.entries.removeAll { entryMatches("app:\(appID)", $0) }
        removeFromFolders(appID: appID, in: &layout)
        return layout
    }

    /// Removes an app from every folder; folders left empty are deleted along
    /// with their grid entries.
    private static func removeFromFolders(appID: String, in layout: inout AppLayout) {
        var folders: [String: LaunchpadFolder] = [:]
        for (id, folder) in layout.folders {
            var folder = folder
            folder.appIDs.removeAll { $0 == appID }
            guard !folder.appIDs.isEmpty else { continue }
            folders[id] = folder
        }
        layout.folders = folders
        layout.entries.removeAll { entry in
            guard case .folder(let folderID) = entry else { return false }
            return layout.folders[folderID] == nil
        }
    }

    /// Deletes a folder and returns its apps to the end of the grid.
    static func delete(folderID: String, in layout: AppLayout) -> AppLayout {
        guard let folder = layout.folders[folderID] else { return layout }
        var layout = layout
        layout.folders.removeValue(forKey: folderID)
        layout.entries.removeAll { entryMatches("folder:\(folderID)", $0) }
        for appID in folder.appIDs {
            layout.entries.append(.app(appID))
        }
        layout.hasCustomOrder = true
        return layout
    }

    private static func entryMatches(_ itemID: String, _ entry: GridEntry) -> Bool {
        switch entry {
        case .app(let appID):
            itemID == "app:\(appID)"
        case .folder(let folderID):
            itemID == "folder:\(folderID)"
        }
    }
}
