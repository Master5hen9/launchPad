import CoreGraphics
import Foundation

/// Pure pagination math for the fullscreen grid, kept free of SwiftUI so it
/// can be unit-tested.
public enum LaunchpadPager {
    public struct Layout {
        public let columns: Int
        public let rows: Int
        public let itemsPerPage: Int
        public let cellWidth: CGFloat
        public let cellHeight: CGFloat
        public let rowSpacing: CGFloat
        public let spacing: CGFloat

        init(columns: Int, rows: Int, cellWidth: CGFloat, cellHeight: CGFloat, rowSpacing: CGFloat, spacing: CGFloat) {
            self.columns = columns
            self.rows = rows
            self.itemsPerPage = columns * rows
            self.cellWidth = cellWidth
            self.cellHeight = cellHeight
            self.rowSpacing = rowSpacing
            self.spacing = spacing
        }
    }

    public static func layout(for size: CGSize) -> Layout {
        // Compact cells so a 1470×956 screen fits 4 rows (about 32 apps/page).
        let cellWidth: CGFloat = 135
        let cellHeight: CGFloat = 150
        let spacing: CGFloat = 20
        let rowSpacing: CGFloat = 18
        let horizontalPadding: CGFloat = 48
        // Space reserved for the page dots and grid margins.
        let verticalReserved: CGFloat = 100

        let columns = max(1, Int((size.width - horizontalPadding * 2 + spacing) / (cellWidth + spacing)))
        let rows = max(1, Int((size.height - verticalReserved + rowSpacing) / (cellHeight + rowSpacing)))
        return Layout(
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            rowSpacing: rowSpacing,
            spacing: spacing
        )
    }

    public static func pages<T>(_ items: [T], itemsPerPage: Int) -> [[T]] {
        guard itemsPerPage > 0, !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: itemsPerPage).map { start in
            Array(items[start..<min(start + itemsPerPage, items.count)])
        }
    }

    /// Maps a point in page coordinates to the flat slot index (0-based within
    /// the page) of the grid cell under it, using the top-left corner of the
    /// page's first cell as the layout anchor. Empty areas map to the nearest
    /// cell; slots beyond the page's current items clamp to the item count so
    /// the drop still lands at a valid insertion point.
    public static func slotIndex(
        at pagePoint: CGPoint,
        anchor: CGPoint,
        layout: Layout,
        itemCountOnPage: Int
    ) -> Int {
        guard itemCountOnPage > 0 else { return 0 }
        let col = Int(round((pagePoint.x - anchor.x) / (layout.cellWidth + layout.spacing)))
        let row = Int(round((pagePoint.y - anchor.y) / (layout.cellHeight + layout.rowSpacing)))
        let clampedCol = min(max(col, 0), layout.columns - 1)
        let clampedRow = min(max(row, 0), layout.rows - 1)
        return min(clampedRow * layout.columns + clampedCol, itemCountOnPage)
    }
}
