import XCTest
@testable import SwingCore

final class TimedRingBufferTests: XCTestCase {
    func testEvictsEntriesOlderThanTheWindow() {
        var buffer = TimedRingBuffer<Int>(window: 1.0)

        for index in 0..<30 {
            buffer.append(index, at: Double(index) * 0.1)
        }

        let span = buffer.span
        XCTAssertNotNil(span)
        XCTAssertGreaterThanOrEqual(span?.lowerBound ?? 0, 1.8)
        XCTAssertEqual(span?.upperBound ?? 0, 2.9, accuracy: 0.0001)
    }

    func testReturnsOnlyTheRequestedSpan() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        for index in 0..<10 {
            buffer.append(index, at: Double(index))
        }

        XCTAssertEqual(buffer.elements(in: 3.0...5.0), [3, 4, 5])
    }

    func testKnowsWhenItDoesNotHoldTheWholeSwing() {
        // A clip harvested from a buffer that no longer reaches back to the
        // address position is truncated, and the segmenter would be reading a
        // partial setup. Better to know before writing the file.
        var buffer = TimedRingBuffer<Int>(window: 2.0)
        for index in 0..<100 {
            buffer.append(index, at: Double(index) * 0.1)
        }

        XCTAssertTrue(buffer.covers(8.5...9.5))
        XCTAssertFalse(buffer.covers(1.0...9.5))
    }

    func testDropsOutOfOrderArrivals() {
        var buffer = TimedRingBuffer<Int>(window: 10)
        buffer.append(1, at: 1.0)
        buffer.append(2, at: 2.0)
        buffer.append(99, at: 1.5)

        XCTAssertEqual(buffer.elements(in: 0...10), [1, 2])
    }

    func testEmptyBufferCoversNothing() {
        let buffer = TimedRingBuffer<Int>(window: 1)

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.span)
        XCTAssertFalse(buffer.covers(0...1))
    }

    func testHoldsEightSecondsOfTwoFortyFramesPerSecond() {
        // The real capture window: 8 s at 240 fps is ~1920 frames resident.
        var buffer = TimedRingBuffer<Int>(window: 8.0)
        let frameDuration = 1.0 / 240.0

        for index in 0..<(240 * 20) {
            buffer.append(index, at: Double(index) * frameDuration)
        }

        XCTAssertGreaterThan(buffer.count, 1900)
        XCTAssertLessThan(buffer.count, 1935)
    }
}
