import CoreGraphics
import Foundation

/// The direction of a four-or-more-finger pinch gesture.
enum PinchDirection: Equatable {
    /// No trigger-worthy movement yet.
    case none
    /// Fingers are converging (pinch in), the gesture that opens the
    /// original Launchpad.
    case inwards
    /// Fingers are spreading apart (pinch out), the gesture that closes it.
    case outwards
}

/// Detects a four-or-more-finger converging or diverging pinch from normalized
/// touch positions (the same coordinate space as `NSTouch.normalizedPosition`).
///
/// The original Launchpad opens on a "thumb and three fingers" pinch; this
/// detector also accepts five fingers and closes on the reverse gesture.
/// Logic is kept free of AppKit so it can be unit-tested.
struct PinchDetector {
    static let minimumTouchCount = 4

    /// Ignore gestures whose fingers start too close together (e.g. a tap or
    /// small rest gesture) so they cannot accidentally trigger. Kept low so
    /// pinches that start on the trackpad edge (where normalized positions
    /// compress) still register.
    static let minimumInitialSpread: CGFloat = 0.08

    /// Trigger when the spread shrinks to this fraction of the maximum spread
    /// observed during the gesture. A higher ratio fires earlier: the event
    /// tap sometimes joins a pinch mid-flight, so requiring only a small
    /// relative shrink keeps the gesture responsive.
    static let pinchRatio: CGFloat = 0.82

    /// Trigger when the spread grows to this multiple of the minimum spread
    /// observed during the gesture.
    static let pinchOutRatio: CGFloat = 1.25

    /// A gesture that goes silent for this long is treated as ended, so a
    /// later gesture cannot inherit stale spread state.
    static let maxSilence: TimeInterval = 0.5

    private var isTracking = false
    private var maxSpread: CGFloat = 0
    private var minSpread: CGFloat = 0
    private var lastSampleTime: TimeInterval = 0
    /// After an inwards trigger, the width the opening pinch started from. A
    /// spread-to-close must exceed it, so a small relaxation bounce right
    /// after the pinch cannot falsely close the just-opened Launchpad.
    private var exitBaseline: CGFloat = 0

    /// Feeds normalized touch positions for each gesture event.
    /// Returns the pinch direction exactly once per gesture, or `.none`;
    /// pass `isEnded: true` for the final event to reset state.
    mutating func process(positions: [CGPoint], isEnded: Bool, now: TimeInterval) -> PinchDirection {
        guard positions.count >= Self.minimumTouchCount else { return .none }
        if isTracking, now - lastSampleTime > Self.maxSilence {
            // The previous gesture stalled or lifted; start fresh.
            reset()
        }
        lastSampleTime = now

        let currentSpread = Self.spread(of: positions)

        if !isTracking {
            isTracking = true
            maxSpread = currentSpread
            minSpread = currentSpread
            if isEnded {
                reset()
            }
            return .none
        }
        maxSpread = max(maxSpread, currentSpread)
        minSpread = min(minSpread, currentSpread)

        var direction: PinchDirection = .none
        if maxSpread >= Self.minimumInitialSpread {
            if currentSpread < maxSpread * Self.pinchRatio {
                direction = .inwards
            } else {
                let requiredSpread = max(exitBaseline, minSpread * Self.pinchOutRatio)
                if currentSpread > requiredSpread {
                    direction = .outwards
                }
            }
        }

        if direction == .inwards {
            exitBaseline = maxSpread
        }

        // Reset immediately: some systems deliver pinch events without
        // `.began`/`.ended` phases, so waiting for an ending event can leave
        // the detector permanently "triggered" and block every later gesture.
        if isEnded || direction != .none {
            resetTracking()
            if isEnded {
                reset()
            }
        }
        return direction
    }

    /// Clears all gesture-tracking state so a fresh gesture can start from
    /// scratch, including any exit baseline. Used when a new gesture begins
    /// without the previous one having delivered its ending event (e.g. an
    /// interrupted pinch).
    mutating func reset() {
        resetTracking()
        exitBaseline = 0
    }

    /// Resets tracking within the current gesture but keeps the exit baseline,
    /// so a converge-then-spread sequence in one continuous gesture still
    /// works as open-then-close.
    private mutating func resetTracking() {
        isTracking = false
        maxSpread = 0
        minSpread = 0
    }

    /// Mean distance of the points from their centroid.
    static func spread(of points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        let count = CGFloat(points.count)
        let centerX = points.reduce(CGFloat(0)) { $0 + $1.x } / count
        let centerY = points.reduce(CGFloat(0)) { $0 + $1.y } / count
        return points.reduce(CGFloat(0)) { $0 + hypot($1.x - centerX, $1.y - centerY) } / count
    }
}
