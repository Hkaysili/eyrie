import Foundation
import Testing
@testable import AwakeKit

@MainActor
private final class SimulatorRecorder {
    var idle: TimeInterval = 0
    var nudges = 0
}

@MainActor
struct ActivitySimulatorTests {
    private func makeSimulator(interval: TimeInterval = 60) -> (ActivitySimulator, SimulatorRecorder) {
        let recorder = SimulatorRecorder()
        let simulator = ActivitySimulator(
            interval: interval,
            idleTime: { recorder.idle },
            nudge: { recorder.nudges += 1 }
        )
        return (simulator, recorder)
    }

    @Test func nudgesWhenIdleCoversInterval() {
        let (simulator, recorder) = makeSimulator()
        recorder.idle = 60
        simulator.tick()
        #expect(recorder.nudges == 1)

        recorder.idle = 59.5 // inside the 1 s grace for an early timer fire
        simulator.tick()
        #expect(recorder.nudges == 2)
    }

    @Test func skipsWhenUserWasActive() {
        let (simulator, recorder) = makeSimulator()
        recorder.idle = 10
        simulator.tick()
        #expect(recorder.nudges == 0, "real input inside the interval must suppress the nudge")
    }

    @Test func startStopLifecycle() {
        let (simulator, _) = makeSimulator()
        #expect(!simulator.isRunning)
        simulator.start()
        #expect(simulator.isRunning)
        simulator.start() // idempotent
        #expect(simulator.isRunning)
        simulator.stop()
        #expect(!simulator.isRunning)
    }

    @Test func startDoesNotNudgeImmediately() async {
        let (simulator, recorder) = makeSimulator()
        recorder.idle = 3600
        simulator.start()
        defer { simulator.stop() }

        await Task.yield()
        #expect(recorder.nudges == 0, "the loop must sleep a full interval before the first check")
    }

    @Test func allIntervalsHaveLabels() {
        for interval in AwakeActivityInterval.allCases {
            #expect(!interval.label.isEmpty)
            #expect(interval.seconds == TimeInterval(interval.rawValue))
        }
    }
}
