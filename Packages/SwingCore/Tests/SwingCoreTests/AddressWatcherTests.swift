import XCTest
@testable import SwingCore

final class AddressWatcherTests: XCTestCase {
    func testArmsOnlyAfterStillnessHasHeld() {
        var watcher = AddressWatcher()

        XCTAssertNil(watcher.update(speed: 0.1, at: 0.0))
        XCTAssertNil(watcher.update(speed: 0.1, at: 0.3), "Too brief to be an address")
        XCTAssertEqual(watcher.update(speed: 0.1, at: 0.7), .held)
        XCTAssertTrue(watcher.isAtAddress)
    }

    func testDoesNotRearmWhileStillAtAddress() {
        var watcher = AddressWatcher()
        _ = watcher.update(speed: 0.1, at: 0.0)
        _ = watcher.update(speed: 0.1, at: 0.7)

        XCTAssertNil(watcher.update(speed: 0.1, at: 1.2))
    }

    func testMovementBreaksAddress() {
        var watcher = AddressWatcher()
        _ = watcher.update(speed: 0.1, at: 0.0)
        _ = watcher.update(speed: 0.1, at: 0.7)

        XCTAssertEqual(watcher.update(speed: 4.0, at: 0.9), .broken)
        XCTAssertFalse(watcher.isAtAddress)
    }

    func testSomeoneWalkingPastNeverArmsUs() {
        var watcher = AddressWatcher()

        for step in 0..<40 {
            let time = Double(step) * 0.05
            // Brief pauses, never held long enough to be an address.
            let speed = step % 4 == 0 ? 0.1 : 2.0
            XCTAssertNil(watcher.update(speed: speed, at: time))
        }
        XCTAssertFalse(watcher.isAtAddress)
    }

    func testRearmsAfterBreakingAndSettlingAgain() {
        var watcher = AddressWatcher()
        _ = watcher.update(speed: 0.1, at: 0.0)
        _ = watcher.update(speed: 0.1, at: 0.7)
        _ = watcher.update(speed: 5.0, at: 0.8)

        XCTAssertNil(watcher.update(speed: 0.1, at: 1.0))
        XCTAssertEqual(watcher.update(speed: 0.1, at: 1.7), .held)
    }
}
