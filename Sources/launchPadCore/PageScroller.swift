import AppKit
import Foundation
import Observation

/// Drives the Launchpad's paging feel: the grid follows the trackpad finger
/// 1:1 while tracking, rubber-bands softly at the edges, and settles on the
/// nearest page with a spring that carries the release velocity, so flicks
/// keep gliding instead of being absorbed by the settle.
@MainActor
@Observable
public final class PageScroller {
    /// Current content offset in points (page * pageWidth when settled).
    public var offset: CGFloat = 0
    public private(set) var pageIndex = 0
    public var pageCount = 1
    public var pageWidth: CGFloat = 800

    private var monitor: Any?
    private var isTracking = false
    private var gestureStartOffset: CGFloat = 0
    private var gestureAccumulatedDelta: CGFloat = 0
    private var recentDeltas: [(delta: CGFloat, time: TimeInterval)] = []
    private var animationTask: Task<Void, Never>?

    private var maxOffset: CGFloat {
        CGFloat(max(pageCount - 1, 0)) * pageWidth
    }

    public init() {}

    public func installMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event
        }
    }

    public func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    public func reset() {
        animationTask?.cancel()
        offset = 0
        pageIndex = 0
        isTracking = false
        recentDeltas.removeAll()
    }

    public func showNext() {
        jump(to: pageIndex + 1)
    }

    public func showPrevious() {
        jump(to: pageIndex - 1)
    }

    public func jump(to page: Int) {
        snap(toPage: page)
    }

    private func handleScrollEvent(_ event: NSEvent) {
        // Momentum is implemented below, so ignore the system's own momentum
        // events that arrive after the fingers leave the trackpad.
        guard event.momentumPhase == [] else { return }

        if event.hasPreciseScrollingDeltas {
            handlePreciseScroll(event)
        } else {
            handleLegacyWheel(event)
        }
    }

    private func handlePreciseScroll(_ event: NSEvent) {
        let phase = event.phase
        if phase.contains(.began) {
            animationTask?.cancel()
            isTracking = true
            gestureStartOffset = offset
            gestureAccumulatedDelta = 0
            recentDeltas.removeAll()
        }

        guard isTracking, phase.contains(.changed) || phase.contains(.ended) else { return }

        gestureAccumulatedDelta += event.scrollingDeltaX
        recordDelta(event.scrollingDeltaX, time: event.timestamp)

        // Content follows the fingers: a negative delta (fingers moving left,
        // with the current direction convention) increases the offset toward
        // the next page.
        offset = rubberBanded(gestureStartOffset - gestureAccumulatedDelta)

        if phase.contains(.ended) || phase.contains(.cancelled) {
            isTracking = false
            finishGesture()
        }
    }

    private func handleLegacyWheel(_ event: NSEvent) {
        let delta = event.scrollingDeltaX
        if delta > 12 {
            showPrevious()
        } else if delta < -12 {
            showNext()
        }
    }

    private func rubberBanded(_ raw: CGFloat) -> CGFloat {
        let resistance: CGFloat = 0.15
        let maxPull: CGFloat = 320

        if raw < 0 {
            let pull = min(maxPull, -raw)
            return -pull * resistance
        }
        if raw > maxOffset {
            let pull = min(maxPull, raw - maxOffset)
            return maxOffset + pull * resistance
        }
        return raw
    }

    private func recordDelta(_ delta: CGFloat, time: TimeInterval) {
        recentDeltas.append((delta, time))
        recentDeltas.removeAll { time - $0.time > 0.12 }
    }

    /// Offset-space velocity (points/second); positive means moving toward
    /// later pages.
    private func estimatedVelocity() -> CGFloat {
        guard recentDeltas.count >= 2 else { return 0 }
        let totalDelta = recentDeltas.reduce(CGFloat(0)) { $0 + $1.delta }
        let duration = (recentDeltas.last?.time ?? 0) - (recentDeltas.first?.time ?? 0)
        guard duration > 0 else { return 0 }
        return -totalDelta / CGFloat(duration)
    }

    private func finishGesture() {
        let velocity = estimatedVelocity()
        let progress = offset / max(pageWidth, 1)

        let targetPage: Int
        if velocity > 300 {
            targetPage = Int(floor(progress)) + 1
        } else if velocity < -300 {
            targetPage = Int(ceil(progress)) - 1
        } else {
            // A slow release still commits once the page is more than a third
            // of the way across, so light swipes turn pages like the original.
            targetPage = Int(floor(progress + 0.35))
        }
        snap(toPage: targetPage)
    }

    private func snap(toPage page: Int) {
        let clamped = min(max(page, 0), max(pageCount - 1, 0))
        let target = CGFloat(clamped) * pageWidth
        pageIndex = clamped
        guard abs(target - offset) > 0.5 else {
            offset = target
            return
        }
        animateSpring(to: target)
    }

    /// Springs the grid to `target`, seeding the spring with the finger's
    /// release velocity. A flick therefore keeps gliding past where the hand
    /// stopped and settles with a slight overshoot, like the original
    /// Launchpad; a gentle release just eases to the nearest page.
    private func animateSpring(to target: CGFloat) {
        animationTask?.cancel()
        let start = offset
        let velocity = min(max(estimatedVelocity(), -2500), 2500)

        // ωn ≈ 17 rad/s, ζ ≈ 0.87: quick settle with a subtle bounce.
        let stiffness: CGFloat = 300
        let damping: CGFloat = 30
        let dt: CGFloat = 1.0 / 120.0
        var x = start
        var v = velocity
        let startTime = ProcessInfo.processInfo.systemUptime

        animationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let acceleration = -stiffness * (x - target) - damping * v
                v += acceleration * dt
                x += v * dt
                self?.offset = x

                if abs(x - target) < 0.5, abs(v) < 50 {
                    self?.offset = target
                    break
                }
                if ProcessInfo.processInfo.systemUptime - startTime > 1.5 {
                    self?.offset = target
                    break
                }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }
}
