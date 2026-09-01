import Foundation
import Testing
@testable import AwakeKit

@MainActor
private final class SimulatorRecorder {
    var idle: TimeInterval = 0
    var nudges = 0
    var ticks = 0
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
        simulator.onTick = { recorder.ticks += 1 }
        return (simulator, recorder)
    }

    @Test func nudgesOnlyWhenIdleCoversThreshold() {
        let (simulator, recorder) = makeSimulator()
        recorder.idle = 60
        simulator.tick()
        #expect(recorder.nudges == 1)

        recorder.idle = 59.5
        simulator.tick()
        #expect(recorder.nudges == 1, "real input inside the threshold must suppress the nudge")

        recorder.idle = 10
        simulator.tick()
        #expect(recorder.nudges == 1)
    }

    /// Pins the timing contract from review: with the wait anchored to the
    /// idle clock, the next check lands exactly when the threshold can be
    /// crossed — never a full extra interval late.
    @Test func nextWaitSchedulesToThresholdCrossing() {
        let (simulator, recorder) = makeSimulator(interval: 300)

        recorder.idle = 0
        #expect(simulator.nextWait() == 300)

        recorder.idle = 290
        #expect(simulator.nextWait() == 10, "last input at t must schedule the nudge for t + interval")

        recorder.idle = 310
        #expect(simulator.nextWait() == 1, "already past the threshold: check almost immediately, never sleep a full interval")
    }

    @Test func tickAlwaysFiresOnTick() {
        let (simulator, recorder) = makeSimulator()
        recorder.idle = 0
        simulator.tick()
        recorder.idle = 60
        simulator.tick()
        #expect(recorder.ticks == 2, "onTick drives the module's trust re-poll, nudge or not")
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
        recorder.idle = 0
        simulator.start()
        defer { simulator.stop() }

        await Task.yield()
        #expect(recorder.nudges == 0, "the loop must sleep before its first check")
    }

    @Test func allIntervalsHaveLabels() {
        for interval in AwakeActivityInterval.allCases {
            #expect(!interval.label.isEmpty)
            #expect(interval.seconds == TimeInterval(interval.rawValue))
        }
    }
}
