import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Observes trackpad gesture events and reports four-or-more-finger pinches:
/// converging pinches (open the original Launchpad) and diverging pinches
/// (close it).
///
/// NSEvent global monitors never see gesture events (they are only delivered
/// to the frontmost app), so a session CGEventTap is used to observe pinches
/// while launchPad runs in the background. Event taps require Accessibility
/// permission; until it is granted the local monitor keeps the foreground case
/// working and the tap is retried automatically.
@MainActor
public final class PinchGestureMonitor {
    private var monitors: [Any] = []
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var trustTimer: Timer?
    private var detector = PinchDetector()
    private let onPinchIn: () -> Void
    private let onPinchOut: () -> Void
    /// Whether gesture events with four or more touches should be swallowed
    /// (not passed on to the system). While the Launchpad is open, its own
    /// exit pinch must not also trip the system's Show Desktop and friends.
    private let isConsumingEnabled: () -> Bool
    /// After a spread-to-close, converging fingers from the same gesture
    /// (often the natural release motion) must not immediately reopen the
    /// Launchpad. A short time window keeps that in check without blocking a
    /// later, deliberate pinch-in.
    private var suppressReopenUntil: TimeInterval = 0

    /// How long a spread-to-close keeps suppressing pinch-in after it fires.
    private static let reopenSuppression: TimeInterval = 0.25

    /// Whether this process is trusted for Accessibility, required for the
    /// global gesture event tap.
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public init(
        onPinchIn: @escaping () -> Void,
        onPinchOut: @escaping () -> Void,
        isConsumingEnabled: @escaping () -> Bool
    ) {
        self.onPinchIn = onPinchIn
        self.onPinchOut = onPinchOut
        self.isConsumingEnabled = isConsumingEnabled
    }

    public func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.gesture, .beginGesture, .endGesture]

        // Global monitor: mostly superseded by the event tap, but kept as an
        // extra channel for systems where gesture events do arrive here.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.forward(event, source: "global")
        }) {
            monitors.append(monitor)
        }

        // Local monitor: covers the case where our own app is frontmost.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.forward(event, source: "local")
            return event
        }) {
            monitors.append(monitor)
        }
        installEventTapIfAccessible()
        Diagnostics.log("monitor started (local + global + tap)")
    }

    public func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        stopTrustPolling()
        removeEventTap()
        Diagnostics.log("monitor stopped")
    }

    /// Extracts gesture data (may be called off the main thread by AppKit),
    /// then hands it to the main actor for stateful processing.
    private func forward(_ event: NSEvent, source: String) {
        guard event.type == .gesture else { return }
        let positions = event.allTouches().map { $0.normalizedPosition }
        let phase = event.phase
        let isEnded = phase.contains(.ended) || phase.contains(.cancelled)
        let isBeginning = phase.contains(.began)

        // The event tap streams a constant feed of single-touch cursor events;
        // only log events that look like an actual gesture.
        if source != "tap"
            || positions.count >= PinchDetector.minimumTouchCount
            || !phase.isEmpty {
            Diagnostics.log("gesture[\(source)] touches=\(positions.count) phase=\(phase.rawValue)")
        }

        // Ignore the flood of single-touch cursor events from the tap.
        guard positions.count >= PinchDetector.minimumTouchCount || isBeginning || isEnded else { return }

        Task { @MainActor [weak self] in
            self?.process(positions: positions, isEnded: isEnded, isBeginning: isBeginning)
        }
    }

    private func process(positions: [CGPoint], isEnded: Bool, isBeginning: Bool) {
        let now = ProcessInfo.processInfo.systemUptime

        // A fresh gesture must never inherit stale state from a previous one
        // whose ending event was lost (e.g. when the overlay opened mid-pinch).
        if isBeginning {
            suppressReopenUntil = 0
            detector.reset()
        }

        switch detector.process(positions: positions, isEnded: isEnded, now: now) {
        case .inwards:
            guard now >= suppressReopenUntil else {
                Diagnostics.log("PINCH IN IGNORED (reopen suppression)")
                return
            }
            Diagnostics.log("PINCH IN DETECTED")
            onPinchIn()
        case .outwards:
            Diagnostics.log("PINCH OUT DETECTED")
            // The same gesture's fingers often converge again while lifting;
            // don't let that reopen what was just closed.
            suppressReopenUntil = now + Self.reopenSuppression
            onPinchOut()
        case .none:
            break
        }
    }

    // MARK: - CGEventTap

    private func installEventTapIfAccessible() {
        guard Self.isAccessibilityTrusted else {
            Diagnostics.log("gesture tap: waiting for accessibility permission")
            startTrustPolling()
            return
        }
        installEventTap()
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        // NSEventType.gesture (29) is not exposed as a public CGEventType, so
        // build the mask from its raw value.
        let gestureMask: CGEventMask = 1 << 29
        // Prefer an active tap so we can swallow gestures while the Launchpad
        // is open; fall back to listen-only if the system rejects it.
        let tap = createEventTap(options: .defaultTap, gestureMask: gestureMask)
            ?? createEventTap(options: .listenOnly, gestureMask: gestureMask)
        guard let tap else {
            Diagnostics.log("gesture tap: creation failed")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Diagnostics.log("gesture tap installed")
    }

    private func createEventTap(
        options: CGEventTapOptions,
        gestureMask: CGEventMask
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: gestureMask,
            callback: { _, _, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PinchGestureMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                let consume = MainActor.assumeIsolated {
                    monitor.handleTapEvent(event)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func removeEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    /// Processes a gesture event from the tap and reports whether the event
    /// should be removed from the stream so the system never sees it.
    private func handleTapEvent(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }
        forward(nsEvent, source: "tap")
        guard isConsumingEnabled(),
              nsEvent.allTouches().count >= PinchDetector.minimumTouchCount else {
            return false
        }
        Diagnostics.log("gesture consumed (launchpad open)")
        return true
    }

    // MARK: - Accessibility polling

    private func startTrustPolling() {
        guard trustTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAccessibilityTrust()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func stopTrustPolling() {
        trustTimer?.invalidate()
        trustTimer = nil
    }

    private func pollAccessibilityTrust() {
        guard Self.isAccessibilityTrusted else { return }
        Diagnostics.log("accessibility permission granted; installing gesture tap")
        stopTrustPolling()
        installEventTap()
    }
}
