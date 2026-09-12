import XCTest
@testable import SwingCore

final class AddressWatcherTests: XCTestCase {
    private let torso = SwingFixture.torsoLength
    private let ball = Point(x: 0.5, y: 0.6)

    /// Feeds the watcher at the pose inference rate and collects what it says.
    private func feed(
        _ watcher: inout AddressWatcher,
        from start: Double,
        to end: Double,
        rate: Double = 60,
        position: (Double) -> Point
    ) -> [(time: Timestamp, event: AddressEvent)] {
        var events: [(time: Timestamp, event: AddressEvent)] = []
        var time = start
        while time <= end {
            if let event = watcher.update(hand: position(time), torsoLength: torso, at: time) {
                events.append((time, event))
            }
            time += 1 / rate
        }
        return events
    }

    func testArmsOnlyAfterStillnessHasHeld() {
        var watcher = AddressWatcher()

        let early = feed(&watcher, from: 0, to: 0.5) { _ in ball }
        XCTAssertTrue(early.isEmpty, "Half a second of stillness is not an address yet")

        let later = feed(&watcher, from: 0.5, to: 1.2) { _ in ball }
        XCTAssertEqual(later.first?.event, .held)
        XCTAssertTrue(watcher.isAtAddress)
    }

    /// The reason the watcher measures spread over a window rather than
    /// frame-to-frame speed: a golfer standing perfectly still still produces a
    /// jittering pose, and speed-based detection would never let them arm.
    func testJitteringPoseStillArms() {
        var generator = SeededGenerator(seed: 11)
        var watcher = AddressWatcher()

        let events = feed(&watcher, from: 0, to: 1.5) { _ in
            let sigma = SwingFixture.jitter(pixels: 4)
            return Point(
                x: ball.x + generator.gaussian(sigma: sigma),
                y: ball.y + generator.gaussian(sigma: sigma)
            )
        }

        XCTAssertEqual(events.first?.event, .held)
        XCTAssertTrue(watcher.isAtAddress)
    }

    func testDoesNotRearmWhileStillAtAddress() {
        var watcher = AddressWatcher()
        _ = feed(&watcher, from: 0, to: 1.2) { _ in ball }

        let more = feed(&watcher, from: 1.2, to: 2.0) { _ in ball }

        XCTAssertTrue(more.isEmpty)
    }

    func testMovementBreaksAddress() {
        var watcher = AddressWatcher()
        _ = feed(&watcher, from: 0, to: 1.2) { _ in ball }

        let swinging = feed(&watcher, from: 1.2, to: 1.6) { time in
            Point(x: ball.x - (time - 1.2) * 0.5, y: ball.y - (time - 1.2) * 0.5)
        }

        XCTAssertEqual(swinging.first?.event, .broken)
        XCTAssertFalse(watcher.isAtAddress)
    }

    func testSomeoneWalkingPastNeverArmsUs() {
        var watcher = AddressWatcher()

        let events = feed(&watcher, from: 0, to: 3.0) { time in
            Point(x: 0.1 + time * 0.2, y: 0.6)
        }

        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(watcher.isAtAddress)
    }

    func testRearmsAfterBreakingAndSettlingAgain() {
        var watcher = AddressWatcher()
        _ = feed(&watcher, from: 0, to: 1.2) { _ in ball }
        _ = feed(&watcher, from: 1.2, to: 1.6) { time in
            Point(x: ball.x - (time - 1.2) * 0.5, y: ball.y)
        }
        XCTAssertFalse(watcher.isAtAddress)

        let again = feed(&watcher, from: 1.6, to: 2.9) { _ in ball }

        XCTAssertEqual(again.first?.event, .held)
        XCTAssertTrue(watcher.isAtAddress)
    }

    func testIgnoresAnUnusableTorsoLength() {
        var watcher = AddressWatcher()

        for step in 0..<80 {
            let event = watcher.update(
                hand: ball, torsoLength: 0, at: Double(step) / 60
            )
            XCTAssertNil(event)
        }
        XCTAssertFalse(watcher.isAtAddress)
    }
}
