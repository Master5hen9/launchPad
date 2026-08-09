import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ContentViewModel {
    private(set) var apps: [AppRecord] = []
    private(set) var items: [LaunchpadItem] = []
    private(set) var openFolderID: String?
    private(set) var isLoading = false
    var searchText = ""

    private var layout = AppLayout()
    private var iconCache: [String: NSImage] = [:]
    private var cellCache: [String: NSImage] = [:]
    private var folderCache: [String: NSImage] = [:]
    private var didLoad = false

    // MARK: - Derived state

    var filteredItems: [LaunchpadItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            switch item {
            case .app(let app):
                !AppFilter.filter([app], query: searchText).isEmpty
            case .folder(let folder):
                folder.name.localizedCaseInsensitiveContains(query)
                    || !AppFilter.filter(folderAppRecords(folder), query: searchText).isEmpty
            }
        }
    }

    var openFolderInfo: (folder: LaunchpadFolder, apps: [AppRecord])? {
        guard let folderID = openFolderID, let folder = layout.folders[folderID] else {
            return nil
        }
        return (folder, folderAppRecords(folder))
    }

    var filteredOpenFolderApps: [AppRecord] {
        guard let info = openFolderInfo else { return [] }
        return AppFilter.filter(info.apps, query: searchText)
    }

    // MARK: - Loading

    func loadAppsIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        // The catalog is warmed at app launch, so this is instant in practice;
        // the spinner only appears when the Launchpad opens before that scan.
        let showLoading = AppCatalog.current == nil
        if showLoading {
            isLoading = true
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }
        let records = await AppCatalog.loadIfNeeded()
        apply(records: records, savedLayout: AppLayoutStore.load())
    }

    /// Rescans the app directories and reconciles the current layout, so apps
    /// installed or removed while the Launchpad is open show up immediately.
    func reloadApps() async {
        let records = await AppCatalog.refresh()
        apply(records: records, savedLayout: layout)
    }

    private func apply(records: [AppRecord], savedLayout: AppLayout?) {
        apps = records
        layout = AppLayout.reconcile(savedLayout, with: records)
        AppLayoutStore.save(layout)
        items = layout.resolvedItems(with: records)
        iconCache.removeAll()
        folderCache.removeAll()
        cellCache.removeAll()
    }

    // MARK: - Folders

    func openFolder(_ folder: LaunchpadFolder) {
        openFolderID = folder.id
    }

    func closeFolder() {
        openFolderID = nil
    }

    /// Drag-and-drop folder creation: dragging one app onto another merges
    /// them into a new folder placed where the target app was.
    func createFolder(dragging sourceAppID: String, onto targetAppID: String) {
        guard sourceAppID != targetAppID else { return }
        mutate { layout in
            AppLayout.makeFolder(
                containing: [sourceAppID, targetAppID],
                named: "文件夹",
                at: targetAppID,
                in: layout
            )
        }
    }

    func addToFolder(appID: String, folderID: String) {
        mutate { AppLayout.add(appID: appID, toFolder: folderID, in: $0) }
    }

    func removeAppFromOpenFolder(_ app: AppRecord) {
        guard let folderID = openFolderID, layout.folders[folderID] != nil else { return }
        mutate { AppLayout.remove(appID: app.id, fromFolder: folderID, in: $0) }
    }

    /// Drag-and-drop sorting inside the open folder: moves the app before
    /// another member (or to the end when `targetAppID` is nil).
    func moveFolderApp(_ appID: String, before targetAppID: String?) {
        guard let folderID = openFolderID, layout.folders[folderID] != nil else { return }
        mutate { AppLayout.move(appID: appID, inFolder: folderID, before: targetAppID, in: $0) }
    }

    func renameFolder(folderID: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { AppLayout.rename(folderID: folderID, to: trimmed, in: $0) }
    }

    func deleteFolder(folderID: String) {
        mutate { AppLayout.delete(folderID: folderID, in: $0) }
        if openFolderID == folderID {
            openFolderID = nil
        }
    }

    // MARK: - Reordering

    /// Moves a grid entry (by `LaunchpadItem.id`) before another entry, or to
    /// the end when `targetItemID` is nil.
    func moveItem(_ itemID: String, before targetItemID: String?) {
        mutate { AppLayout.move(entryID: itemID, before: targetItemID, in: $0) }
    }

    /// Moves a grid entry so it lands at `index` within the currently visible
    /// (possibly search-filtered) item list.
    func moveItem(_ itemID: String, toIndexInFiltered index: Int) {
        let itemIDs = filteredItems.map(\.id)
        guard itemIDs.contains(itemID) else { return }
        let targetID = index < itemIDs.count ? itemIDs[index] : nil
        if let targetID, targetID == itemID {
            return
        }
        moveItem(itemID, before: targetID)
    }

    // MARK: - Artwork

    func artwork(for item: LaunchpadItem) -> NSImage {
        switch item {
        case .app(let app):
            cellImage(for: app)
        case .folder(let folder):
            folderImage(for: folder)
        }
    }

    func icon(for app: AppRecord) -> NSImage {
        if let cached = iconCache[app.id] {
            return cached
        }
        let source = NSWorkspace.shared.icon(forFile: app.url.path)
        let rendered = Self.renderedIcon(from: source, pixelSize: 228)
        iconCache[app.id] = rendered
        return rendered
    }

    /// A single pre-rendered image for an app cell (icon + label + shadows),
    /// baked at high resolution so the entrance animation only moves one layer
    /// per cell instead of re-rendering a view tree every frame.
    func cellImage(for app: AppRecord) -> NSImage {
        if let cached = cellCache[app.id] {
            return cached
        }
        let content = LaunchpadCellArtwork(icon: icon(for: app), name: app.name)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.nsImage else {
            return icon(for: app)
        }
        cellCache[app.id] = image
        return image
    }

    func folderImage(for folder: LaunchpadFolder) -> NSImage {
        let key = "\(folder.id)|\(folder.name)|\(folder.appIDs.joined(separator: ","))"
        if let cached = folderCache[key] {
            return cached
        }
        let icons = folderAppRecords(folder).prefix(4).map { icon(for: $0) }
        let content = LaunchpadFolderArtwork(folder: folder, icons: Array(icons))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.nsImage else {
            return NSImage(
                systemSymbolName: "folder.fill",
                accessibilityDescription: folder.name
            ) ?? NSImage()
        }
        folderCache[key] = image
        return image
    }

    // MARK: - App actions

    /// Whether the app bundle can be moved to the Trash. System apps under
    /// `/System` are protected, and read-only volumes can't be modified.
    func canUninstall(_ app: AppRecord) -> Bool {
        !app.url.path.hasPrefix("/System/")
            && FileManager.default.isWritableFile(atPath: app.url.path)
    }

    /// Hides the app from the Launchpad grid. The app stays installed and can
    /// be restored from Settings (see `HiddenAppsStore`).
    func hide(_ app: AppRecord) {
        mutate { AppLayout.hide(appID: app.id, in: $0) }
        clearCaches(for: app)
    }

    /// Moves the app bundle to the Trash and removes it from the layout.
    func uninstall(_ app: AppRecord) throws {
        var trashURL: NSURL?
        try FileManager.default.trashItem(at: app.url, resultingItemURL: &trashURL)
        mutate { AppLayout.removeDeleted(appID: app.id, in: $0) }
        clearCaches(for: app)
    }

    func launch(_ app: AppRecord) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("Failed to launch %@: %@", app.url.path, error.localizedDescription)
            }
        }
    }

    func revealInFinder(_ app: AppRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    // MARK: - Private

    private func mutate(_ transform: (AppLayout) -> AppLayout) {
        layout = transform(layout)
        items = layout.resolvedItems(with: apps)
        folderCache.removeAll()
        AppLayoutStore.save(layout)
    }

    private func folderAppRecords(_ folder: LaunchpadFolder) -> [AppRecord] {
        let map = appMap
        return folder.appIDs.compactMap { map[$0] }
    }

    private var appMap: [String: AppRecord] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
    }

    private func clearCaches(for app: AppRecord) {
        iconCache.removeValue(forKey: app.id)
        cellCache.removeValue(forKey: app.id)
    }

    /// Renders a workspace icon once into a fixed-resolution bitmap so views
    /// composite a plain layer instead of re-rendering the (often multi-rep or
    /// vector) source image on every animation frame. 228 px covers the 76 pt
    /// icon at up to 3× display scale.
    private static func renderedIcon(from source: NSImage, pixelSize: Int) -> NSImage {
        let pointSize = NSSize(width: 76, height: 76)
        let image = NSImage(size: pointSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source
        }
        image.addRepresentation(rep)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: pointSize))
        image.unlockFocus()
        return image
    }
}

/// Static artwork for one Launchpad cell: the icon, label, and shadows, laid
/// out exactly like the live cell and rendered once into a bitmap.
private struct LaunchpadCellArtwork: View {
    let icon: NSImage
    let name: String

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 135, height: 150)
    }
}

/// Static artwork for a folder cell: the original Launchpad look, with the
/// first few contained app icons arranged in a mini grid, label, and shadow,
/// rendered once into a bitmap just like app cells.
private struct LaunchpadFolderArtwork: View {
    let folder: LaunchpadFolder
    let icons: [NSImage]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18))
                if icons.isEmpty {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    miniIconGrid
                }
            }
            .frame(width: 76, height: 76)
            .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 135, height: 150)
    }

    private var miniIconGrid: some View {
        let rows = stride(from: 0, to: icons.count, by: 2).map { rowStart in
            Array(icons[rowStart..<min(rowStart + 2, icons.count)])
        }
        return VStack(spacing: 6) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(0..<rows[rowIndex].count, id: \.self) { iconIndex in
                        Image(nsImage: rows[rowIndex][iconIndex])
                            .resizable()
                            .frame(width: 28, height: 28)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                }
            }
        }
    }
}
