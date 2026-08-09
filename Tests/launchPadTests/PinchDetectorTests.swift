import CoreGraphics
import Foundation
import Testing
@testable import launchPadCore

struct PinchDetectorTests {
    private func square(radius: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: 0.5 - radius, y: 0.5 - radius),
            CGPoint(x: 0.5 + radius, y: 0.5 - radius),
            CGPoint(x: 0.5 - radius, y: 0.5 + radius),
            CGPoint(x: 0.5 + radius, y: 0.5 + radius)
        ]
    }

    @Test func spreadMeasuresMeanDistanceFromCentroid() {
        let spread = PinchDetector.spread(of: square(radius: 0.1))
        #expect(abs(spread - sqrt(2) * 0.1) < 0.0001)
    }

    @Test func convergingFourFingerPinchTriggers() {
        var detector = PinchDetector()
        let first = detector.process(positions: square(radius: 0.25), isEnded: false, now: 1)
        let second = detector.process(positions: square(radius: 0.12), isEnded: false, now: 1.05)
        #expect(first == .none)
        #expect(second == .inwards)
    }

    @Test func fewerThanFourTouchesNeverTriggers() {
        var detector = PinchDetector()
        let first = detector.process(positions: Array(square(radius: 0.25).prefix(3)), isEnded: false, now: 1)
        let second = detector.process(positions: Array(square(radius: 0.1).prefix(3)), isEnded: false, now: 1.05)
        #expect(first == .none)
        #expect(second == .none)
    }

    @Test func divergingFourFingerPinchTriggers() {
        var detector = PinchDetector()
        let first = detector.process(positions: square(radius: 0.1), isEnded: false, now: 1)
        let second = detector.process(positions: square(radius: 0.25), isEnded: false, now: 1.05)
        let third = detector.process(positions: square(radius: 0.3), isEnded: false, now: 1.1)
        #expect(first == .none)
        #expect(second == .outwards)
        #expect(third == .none)
    }

    @Test func tinyExpansionDoesNotTrigger() {
        var detector = PinchDetector()
        let first = detector.process(positions: square(radius: 0.2), isEnded: false, now: 1)
        let second = detector.process(positions: square(radius: 0.24), isEnded: false, now: 1.05)
        #expect(first == .none)
        #expect(second == .none)
    }

    @Test func triggersOnlyOncePerGesture() {
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 1)
        let first = detector.process(positions: square(radius: 0.1), isEnded: false, now: 1.05)
        let second = detector.process(positions: square(radius: 0.08), isEnded: false, now: 1.1)
        #expect(first == .inwards)
        #expect(second == .none)
    }

    @Test func endingGestureAllowsNewTrigger() {
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 1)
        let triggered = detector.process(positions: square(radius: 0.1), isEnded: true, now: 1.05)
        #expect(triggered == .inwards)
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 2)
        let again = detector.process(positions: square(radius: 0.1), isEnded: false, now: 2.05)
        #expect(again == .inwards)
    }

    @Test func resetAllowsNewGestureWithoutEndedEvent() {
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 1)
        let triggered = detector.process(positions: square(radius: 0.1), isEnded: false, now: 1.05)
        #expect(triggered == .inwards)

        // Simulate an interrupted gesture whose ending event never arrived.
        detector.reset()
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 2)
        let again = detector.process(positions: square(radius: 0.1), isEnded: false, now: 2.05)
        #expect(again == .inwards)
    }

    @Test func tinyInitialSpreadDoesNotTrigger() {
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.02), isEnded: false, now: 1)
        let result = detector.process(positions: square(radius: 0.005), isEnded: false, now: 1.05)
        #expect(result == .none)
    }

    @Test func smallConvergenceTriggers() {
        // A 25% shrink is enough now: the old 70%-of-max requirement would
        // have missed this gentler pinch.
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.2), isEnded: false, now: 1)
        let result = detector.process(positions: square(radius: 0.15), isEnded: false, now: 1.05)
        #expect(result == .inwards)
    }

    @Test func silentGapStartsWithFreshState() {
        // A stalled gesture must not leak its wide spread into the next one,
        // which would otherwise falsely trigger a pinch-in on the first frame.
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.3), isEnded: false, now: 1)
        let result = detector.process(positions: square(radius: 0.1), isEnded: false, now: 2)
        #expect(result == .none)
    }

    @Test func relaxationAfterOpenDoesNotClose() {
        // After a pinch-in opens the Launchpad, fingers often bounce back a
        // little. That must not read as a spread-to-close; only spreading
        // back past the opening width may close.
        var detector = PinchDetector()
        _ = detector.process(positions: square(radius: 0.25), isEnded: false, now: 1)
        let opened = detector.process(positions: square(radius: 0.12), isEnded: false, now: 1.05)
        #expect(opened == .inwards)

        let bounce = detector.process(positions: square(radius: 0.18), isEnded: false, now: 1.1)
        let bounceAgain = detector.process(positions: square(radius: 0.2), isEnded: false, now: 1.15)
        #expect(bounce == .none)
        #expect(bounceAgain == .none)

        let closed = detector.process(positions: square(radius: 0.26), isEnded: false, now: 1.2)
        #expect(closed == .outwards)
    }
}
