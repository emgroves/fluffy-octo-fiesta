import XCTest
@testable import SwingCore

final class SwingStateMachineTests: XCTestCase {
    func testImpactIsIgnoredUntilTheGolferIsAtAddress() {
        // This is the whole defence against a neighbouring bay. The microphone
        // hears every strike on the range; only the pose gate says it was ours.
        var machine = SwingStateMachine()

        machine.handle(.impactHeard(1.0))
        XCTAssertEqual(machine.state, .idle)

        machine.handle(.personAppeared)
        machine.handle(.impactHeard(2.0))
        XCTAssertEqual(machine.state, .framing, "Framing is not armed")
    }

    func testImpactIsHonouredOnceArmed() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)

        machine.handle(.impactHeard(4.25))

        XCTAssertEqual(machine.state, .capturing(impact: 4.25))
    }

    func testFullHandsFreeLoopReturnsToFramingReadyForTheNextBall() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)
        machine.handle(.impactHeard(4.25))

        let harvest = machine.handle(.captureWindowElapsed)
        XCTAssertTrue(harvest.contains(.harvestClip(impact: 4.25)))
        XCTAssertTrue(
            harvest.contains(.stopPoseTracking),
            "Inference should pause for the replay stretch — it is our cheapest thermal saving"
        )

        let replay = machine.handle(.segmentationSucceeded)
        XCTAssertEqual(machine.state, .replaying)
        XCTAssertTrue(replay.contains(.startReplay))

        let done = machine.handle(.replayFinished)
        XCTAssertEqual(machine.state, .framing)
        XCTAssertTrue(done.contains(.startPoseTracking))
        XCTAssertTrue(done.contains(.returnToLive))
    }

    func testFailedSegmentationReturnsToLiveWithoutReplaying() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)
        machine.handle(.impactHeard(1.0))
        machine.handle(.captureWindowElapsed)

        let effects = machine.handle(.segmentationFailed)

        XCTAssertEqual(machine.state, .framing)
        XCTAssertFalse(effects.contains(.startReplay))
        XCTAssertTrue(effects.contains(.startPoseTracking))
    }

    func testBreakingAddressDisarms() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)
        XCTAssertEqual(machine.state, .armed)

        machine.handle(.addressBroken)

        XCTAssertEqual(machine.state, .framing)
    }

    func testWalkingOutOfFrameReturnsToIdle() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)

        let effects = machine.handle(.personDisappeared)

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(effects.contains(.stopPoseTracking))
    }

    func testResetFromReplayStopsPlayback() {
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)
        machine.handle(.impactHeard(1.0))
        machine.handle(.captureWindowElapsed)
        machine.handle(.segmentationSucceeded)

        let effects = machine.handle(.reset)

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(effects.contains(.stopReplay))
    }

    func testDuplicateAndLateInputsAreHarmless() {
        // Pose and audio arrive on separate queues; repeats are normal traffic.
        var machine = SwingStateMachine()
        machine.handle(.personAppeared)
        machine.handle(.personAppeared)
        machine.handle(.addressHeld)
        machine.handle(.addressHeld)

        XCTAssertEqual(machine.state, .armed)
        XCTAssertTrue(machine.handle(.replayFinished).isEmpty)
        XCTAssertEqual(machine.state, .armed)
    }
}
