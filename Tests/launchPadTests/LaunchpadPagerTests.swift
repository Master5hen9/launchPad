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
}
