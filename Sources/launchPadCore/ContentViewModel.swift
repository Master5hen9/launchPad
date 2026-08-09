import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ContentViewModel {
    private(set) var apps: [AppRecord] = []
    private(set) var isLoading = false
    var searchText = ""

    private var iconCache: [String: NSImage] = [:]
    private var cellCache: [String: NSImage] = [:]
    private var didLoad = false

    var filteredApps: [AppRecord] {
        AppFilter.filter(apps, query: searchText)
    }

    func loadAppsIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        defer { isLoading = false }

        let records = await Task.detached(priority: .userInitiated) {
            AppScanner.scan()
        }.value
        // Pre-render every cell's artwork while the loading spinner is still
        // visible, so the fly-in starts with plain cached images and never
        // builds views on its first frames.
        renderCellArtwork(for: records)
        apps = records
        iconCache.removeAll()
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

    /// A single pre-rendered image for a cell (icon + label + shadows), baked
    /// at high resolution so the entrance animation only moves one layer per
    /// cell instead of re-rendering a view tree every frame.
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

    private func renderCellArtwork(for records: [AppRecord]) {
        for app in records {
            _ = cellImage(for: app)
        }
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
