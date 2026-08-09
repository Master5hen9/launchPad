import CoreGraphics
import Testing
@testable import launchPadCore

struct LaunchpadPagerTests {
    @Test func pagesChunkItems() {
        let pages = LaunchpadPager.pages(Array(0..<10), itemsPerPage: 4)
        #expect(pages == [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]])
    }

    @Test func emptyItemsProduceNoPages() {
        #expect(LaunchpadPager.pages([Int](), itemsPerPage: 4).isEmpty)
    }

    @Test func layoutFillsLargeScreen() {
        let layout = LaunchpadPager.layout(for: CGSize(width: 1728, height: 1117))
        #expect(layout.columns >= 6)
        #expect(layout.rows >= 2)
        #expect(layout.itemsPerPage == layout.columns * layout.rows)
    }

    @Test func layoutFitsFourRowsOnUserScreen() {
        // 1470×956 screen minus the search bar area (~838pt of grid height).
        let layout = LaunchpadPager.layout(for: CGSize(width: 1470, height: 838))
        #expect(layout.rows == 4)
        #expect(layout.columns >= 6)
    }

    @Test func layoutNeverZero() {
        let layout = LaunchpadPager.layout(for: CGSize(width: 300, height: 300))
        #expect(layout.columns >= 1)
        #expect(layout.rows >= 1)
        #expect(layout.itemsPerPage >= 1)
    }

    @Test func slotIndexMapsCursorToNearestCell() {
        let layout = LaunchpadPager.Layout(
            columns: 5,
            rows: 6,
            cellWidth: 135,
            cellHeight: 150,
            rowSpacing: 18,
            spacing: 20
        )
        let anchor = CGPoint(x: 48, y: 8)

        // Center of column 1, row 0.
        #expect(
            LaunchpadPager.slotIndex(
                at: CGPoint(x: 48 + 155 + 67, y: 8 + 75),
                anchor: anchor,
                layout: layout,
                itemCountOnPage: 20
            ) == 1
        )
        // Center of row 1, column 0.
        #expect(
            LaunchpadPager.slotIndex(
                at: CGPoint(x: 48 + 67, y: 8 + 168 + 75),
                anchor: anchor,
                layout: layout,
                itemCountOnPage: 20
            ) == 5
        )
    }

    @Test func slotIndexClampsToPageBoundsAndItemCount() {
        let layout = LaunchpadPager.Layout(
            columns: 5,
            rows: 6,
            cellWidth: 135,
            cellHeight: 150,
            rowSpacing: 18,
            spacing: 20
        )
        let anchor = CGPoint(x: 48, y: 8)

        // A slot beyond the items on the page clamps to the item count.
        #expect(
            LaunchpadPager.slotIndex(
                at: CGPoint(x: 48 + 155 * 2 + 67, y: 8 + 168 * 3 + 75),
                anchor: anchor,
                layout: layout,
                itemCountOnPage: 10
            ) == 10
        )
        // Far outside the grid clamps to the bottom-right cell.
        #expect(
            LaunchpadPager.slotIndex(
                at: CGPoint(x: 10_000, y: 10_000),
                anchor: anchor,
                layout: layout,
                itemCountOnPage: 30
            ) == 29
        )
        // An empty page has no insertable slot.
        #expect(
            LaunchpadPager.slotIndex(
                at: CGPoint(x: 100, y: 100),
                anchor: anchor,
                layout: layout,
                itemCountOnPage: 0
            ) == 0
        )
    }
}
