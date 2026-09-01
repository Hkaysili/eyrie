import SwiftUI
import EyrieCore

/// Keep-awake sessions backed by IOKit power assertions (Amphetamine core).
@MainActor
@Observable
public final class AwakeModule: EyrieModule {
    public let id = "awake"
    public let name = "Keep Awake"
    public var symbolName: String { isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves" }

    public var isActive: Bool { isSessionActive || isSimulatingActivity }

    /// Whether a keep-awake power assertion session is running.
    public private(set) var isSessionActive = false
    /// Whether the activity simulator's tick loop is running. Mirrors the
    /// simulator so `@Observable` tracking sees the change.
    public private(set) var isSimulatingActivity = false
    /// Nil while active means the session runs until manually stopped.
    public private(set) var sessionEndDate: Date?

    public var selectedPreset: AwakePreset {
        didSet { defaults.set(selectedPreset.rawValue, forKey: Self.presetKey) }
    }

    /// When true the display may sleep while the system stays awake.
    public var allowDisplaySleep: Bool {
        didSet {
            defaults.set(allowDisplaySleep, forKey: Self.displaySleepKey)
            if isActive { holdAssertion() }
        }
    }

    /// Periodically nudges the pointer while the user is idle so chat apps
    /// don't mark them away. Runs with the panel closed, so enable/disable
    /// goes through `setModuleEnabled(_:)`, not view lifecycle.
    public var simulateActivity: Bool {
        didSet {
            defaults.set(simulateActivity, forKey: Self.simulateActivityKey)
            syncSimulator()
            if simulateActivity, !ActivitySimulator.hasAccessibilityTrust {
                ActivitySimulator.promptForAccessibilityTrust()
            }
        }
    }

    public var activityInterval: AwakeActivityInterval {
        didSet {
            defaults.set(activityInterval.rawValue, forKey: Self.activityIntervalKey)
            simulator.interval = activityInterval.seconds
        }
    }

    /// Whether synthetic events will actually be delivered; drives the
    /// caution line in the panel.
    public var hasAccessibilityTrust: Bool { ActivitySimulator.hasAccessibilityTrust }

    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let simulator: ActivitySimulator
    /// The registry calls `setModuleEnabled(_:)` at launch, so the simulator
    /// stays parked until then even when the preference is on.
    @ObservationIgnored private var isModuleEnabled = false

    private static let presetKey = "awake.preset"
    private static let displaySleepKey = "awake.allowDisplaySleep"
    private static let simulateActivityKey = "awake.simulateActivity"
    private static let activityIntervalKey = "awake.activityInterval"

    public init() {
        selectedPreset = AwakePreset(rawValue: defaults.integer(forKey: Self.presetKey)) ?? .indefinite
        allowDisplaySleep = defaults.bool(forKey: Self.displaySleepKey)
        simulateActivity = defaults.bool(forKey: Self.simulateActivityKey)
        let interval = AwakeActivityInterval(rawValue: defaults.integer(forKey: Self.activityIntervalKey)) ?? .minute1
        activityInterval = interval
        simulator = ActivitySimulator(interval: interval.seconds)
    }

    public func start() {
        sessionTask?.cancel()
        guard holdAssertion() else { return }
        isSessionActive = true

        if let minutes = selectedPreset.minutes {
            let end = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
            sessionEndDate = end
            sessionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.sessionExpired()
            }
        } else {
            sessionEndDate = nil
        }
    }

    public func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        sessionEndDate = nil
        isSessionActive = false
        PowerAssertionService.shared.release(token: id)
    }

    /// The kernel drops assertions with the process, but releasing explicitly
    /// keeps `pmset -g assertions` clean even if termination is slow.
    public func shutdown() {
        stop()
        simulator.stop()
        isSimulatingActivity = false
    }

    public func setModuleEnabled(_ enabled: Bool) {
        isModuleEnabled = enabled
        if !enabled { stop() }
        syncSimulator()
    }

    private func syncSimulator() {
        let shouldRun = simulateActivity && isModuleEnabled
        if shouldRun, !simulator.isRunning {
            simulator.start()
        } else if !shouldRun, simulator.isRunning {
            simulator.stop()
        }
        isSimulatingActivity = simulator.isRunning
    }

    @discardableResult
    private func holdAssertion() -> Bool {
        PowerAssertionService.shared.hold(
            token: id,
            mode: allowDisplaySleep ? .allowDisplaySleep : .preventDisplaySleep,
            reason: "Eyrie Keep Awake session"
        )
    }

    private func sessionExpired() {
        stop()
        Task {
            await NotificationService.shared.send(
                title: "Keep Awake ended",
                body: "The session finished — your Mac can sleep again."
            )
        }
    }

    public var panelContent: AnyView { AnyView(AwakePanelView(module: self)) }
    public var panelAccessory: AnyView { AnyView(AwakeToggle(module: self)) }
    public var settingsContent: AnyView { AnyView(AwakeSettingsView(module: self)) }
}

public enum AwakePreset: Int, CaseIterable, Identifiable, Sendable {
    case indefinite = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case hours4 = 240
    case hours8 = 480

    public var id: Int { rawValue }

    /// Nil means run indefinitely.
    public var minutes: Int? { self == .indefinite ? nil : rawValue }

    public var label: String {
        switch self {
        case .indefinite: "Indefinitely"
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .hour1: "1 hour"
        case .hours2: "2 hours"
        case .hours4: "4 hours"
        case .hours8: "8 hours"
        }
    }
}
