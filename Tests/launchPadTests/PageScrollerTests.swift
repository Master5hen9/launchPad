import Foundation
import Testing
@testable import launchPadCore

@MainActor
struct PageScrollerTests {
    @Test func normalizeKeepsCurrentPageWhenPossible() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.normalize(pageCount: 4)
        scroller.jump(to: 2)

        scroller.normalize(pageCount: 3)

        #expect(scroller.pageIndex == 2)
        #expect(scroller.offset == 2000)
    }

    @Test func normalizeClampsToLastValidPage() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.normalize(pageCount: 4)
        scroller.jump(to: 3)

        scroller.normalize(pageCount: 2)

        #expect(scroller.pageIndex == 1)
        #expect(scroller.offset == 1000)
    }

    @Test func normalizeWithSinglePageResets() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.jump(to: 5)

        scroller.normalize(pageCount: 1)

        #expect(scroller.pageIndex == 0)
        #expect(scroller.offset == 0)
    }

    @Test func dragMovesContentOneToOne() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.normalize(pageCount: 3)

        scroller.beginDrag()
        scroller.updateDrag(translation: -400, time: 1.0)
        scroller.updateDrag(translation: -480, time: 1.05)
        scroller.updateDrag(translation: -520, time: 1.1)

        // Offset follows the pointer exactly (no snapping mid-drag).
        #expect(scroller.offset == 520)

        scroller.endDrag()
        #expect(scroller.pageIndex == 1)
    }

    @Test func dragRightGoesBackToPreviousPage() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.normalize(pageCount: 3)
        scroller.jump(to: 2)
        scroller.normalize(pageCount: 3)

        scroller.beginDrag()
        scroller.updateDrag(translation: 500, time: 1.0)
        scroller.updateDrag(translation: 560, time: 1.05)
        scroller.updateDrag(translation: 600, time: 1.1)

        #expect(scroller.offset == 1400)  // 2000 - 600

        scroller.endDrag()
        #expect(scroller.pageIndex == 1)
    }

    @Test func smallDragSettlesBackToCurrentPage() {
        let scroller = PageScroller()
        scroller.pageWidth = 1000
        scroller.normalize(pageCount: 3)

        scroller.beginDrag()
        scroller.updateDrag(translation: -20, time: 1.0)
        scroller.updateDrag(translation: -25, time: 1.05)
        scroller.updateDrag(translation: -30, time: 1.1)

        scroller.endDrag()

        #expect(scroller.pageIndex == 0)
    }
}
