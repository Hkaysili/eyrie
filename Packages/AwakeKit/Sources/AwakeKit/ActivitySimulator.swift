import ApplicationServices
import CoreGraphics
import Foundation

/// Posts a tiny synthetic mouse move on a fixed period while the user is
/// genuinely idle, so presence-based apps (Teams, Slack, …) don't flip the
/// user to "away" on a machine Keep Awake is holding open.
///
/// A nudge fires only when the HID idle time covers the whole interval, so it
/// never fights real input. The loop sleeps *before* the first check — enabling
/// the switch must never move the pointer immediately, and tests rely on this
/// to exercise start/stop without posting real events.
@MainActor
final class ActivitySimulator {
    private(set) var isRunning = false

    /// Seconds between checks; also the idle threshold that allows a nudge.
    var interval: TimeInterval

    private let idleTime: @MainActor () -> TimeInterval
    private let nudge: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(
        interval: TimeInterval,
        idleTime: @escaping @MainActor () -> TimeInterval = ActivitySimulator.systemIdleTime,
        nudge: @escaping @MainActor () -> Void = ActivitySimulator.postMouseNudge
    ) {
        self.interval = interval
        self.idleTime = idleTime
        self.nudge = nudge
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.interval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// One idle check; split from the loop so tests drive it synchronously.
    /// The 1 s grace keeps a nudge from being skipped when the timer fires
    /// marginally before the idle clock catches up.
    func tick() {
        if idleTime() >= interval - 1 { nudge() }
    }

    // MARK: - System implementations

    /// `kCGAnyInputEventType` isn't imported into Swift; its C definition is
    /// `((CGEventType)(~0))`.
    static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    /// Moves the pointer 1 pt right and immediately back. Both events reset
    /// the HID idle clock; restoring keeps the cursor visually in place.
    static func postMouseNudge() {
        guard let location = CGEvent(source: nil)?.location else { return }
        let nudged = CGPoint(x: location.x + 1, y: location.y)
        for point in [nudged, location] {
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }

    /// Posting synthetic events needs the Accessibility (TCC) grant.
    static var hasAccessibilityTrust: Bool { AXIsProcessTrusted() }

    static func promptForAccessibilityTrust() {
        // The unbundled swift-test runner must never raise the TCC prompt
        // (same guard as NotificationService).
        guard Bundle.main.bundleIdentifier != nil else { return }
        // Literal key: `kAXTrustedCheckOptionPrompt` is a C global Swift 6
        // rejects as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

/// How often the simulator checks for idleness and nudges the pointer.
public enum AwakeActivityInterval: Int, CaseIterable, Identifiable, Sendable {
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120
    case minutes5 = 300

    public var id: Int { rawValue }

    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var label: String {
        switch self {
        case .seconds30: "30 seconds"
        case .minute1: "1 minute"
        case .minutes2: "2 minutes"
        case .minutes5: "5 minutes"
        }
    }
}
