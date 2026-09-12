import XCTest
@testable import SwingCore

final class SwingSegmenterTests: XCTestCase {
    private let segmenter = SwingSegmenter()

    /// Midpoint of the scripted pause at the top, which is what the segmenter
    /// resolves to when it looks for the hands' furthest point.
    private func expectedTop(_ script: SwingFixture.Script) -> Double {
        (script.topStart + script.topEnd) / 2
    }

    func testLocatesEveryKeyMomentOfAScriptedSwing() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.08)
        XCTAssertEqual(result.top, expectedTop(script), accuracy: 0.08)
        XCTAssertEqual(result.impact, script.impact, accuracy: 0.001)
        XCTAssertEqual(result.finish, script.followThroughEnd, accuracy: 0.08)
        XCTAssertLessThan(result.address, result.takeaway)
        XCTAssertTrue(result.isMonotonic)
    }

    /// The regression this whole measurement exists for.
    ///
    /// The first version of this segmenter thresholded frame-to-frame hand
    /// speed. Differentiating a pose track multiplies position jitter by the
    /// inference rate, so at two pixels of jitter it reported the top of the
    /// backswing at 0.98 s when the truth was 1.75 s — it mistook a noise dip
    /// during the address for the top. At eight pixels it failed outright.
    func testSurvivesRealisticPoseJitter() throws {
        let script = SwingFixture.Script()

        for pixels in [1.0, 2.0, 4.0, 8.0] {
            let track = SwingFixture.track(
                script: script,
                jitter: SwingFixture.jitter(pixels: pixels)
            )

            let result = try segmenter.segment(track: track, impact: script.impact)

            XCTAssertEqual(
                result.takeaway, script.takeaway, accuracy: 0.10,
                "takeaway drifted at \(pixels)px of jitter"
            )
            XCTAssertEqual(
                result.top, expectedTop(script), accuracy: 0.10,
                "top drifted at \(pixels)px of jitter"
            )
            XCTAssertEqual(
                result.finish, script.followThroughEnd, accuracy: 0.10,
                "finish drifted at \(pixels)px of jitter"
            )
            XCTAssertTrue(result.isMonotonic)
        }
    }

    func testTempoRatioMatchesTheScriptedSwing() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)
        let ratio = try XCTUnwrap(result.tempoRatio)

        // Roughly 0.75 s back against 0.28 s down — near the 3:1 golfers quote.
        XCTAssertEqual(ratio, 2.7, accuracy: 0.5)
    }

    func testClipRangeCoversTheWholeSwingWithPadding() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)
        let range = result.clipRange()

        XCTAssertLessThan(range.lowerBound, result.address)
        XCTAssertGreaterThan(range.upperBound, result.finish)
        XCTAssertLessThan(range.upperBound - range.lowerBound, 5.0, "Clips should stay short")
    }

    func testRejectsAnImpactOutsideTheTrack() {
        let track = SwingFixture.track()

        XCTAssertThrowsError(try segmenter.segment(track: track, impact: 99)) { error in
            XCTAssertEqual(error as? SegmentationFailure, .impactOutsideTrack)
        }
    }

    func testRejectsATrackWithTooFewSamples() {
        let track = PoseTrack(samples: [])

        XCTAssertThrowsError(try segmenter.segment(track: track, impact: 1)) { error in
            XCTAssertEqual(error as? SegmentationFailure, .insufficientSamples)
        }
    }

    func testSurvivesDroppedPoseFrames() throws {
        // Vision will not return a usable pose on every frame outdoors. Losing a
        // scattering of them must not move the key moments.
        let script = SwingFixture.Script()
        let full = SwingFixture.track(script: script)
        var thinned = PoseTrack()
        for (index, sample) in full.samples.enumerated() where index % 7 != 3 {
            thinned.append(sample)
        }

        let result = try segmenter.segment(track: thinned, impact: script.impact)

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.10)
        XCTAssertEqual(result.top, expectedTop(script), accuracy: 0.10)
        XCTAssertTrue(result.isMonotonic)
    }

    /// A slow backswing is the case that exposes the difference between "settled"
    /// and "settled for a while".
    ///
    /// Spread within a window scales with hand speed, so the slower the swing the
    /// closer the pause at the top sits to the stillness threshold — at a 1.25 s
    /// backswing it drops under it. An earlier version stopped its backward walk
    /// there and called the top of the backswing the takeaway.
    func testHandlesASlowerSwing() throws {
        var script = SwingFixture.Script()
        script.topStart = 2.25
        script.topEnd = 2.30
        script.impact = 2.70
        script.followThroughEnd = 3.20
        script.trackEnd = 4.00
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.08)
        XCTAssertEqual(result.top, expectedTop(script), accuracy: 0.08)
        XCTAssertTrue(result.isMonotonic)
    }

    /// The bay next door, caught a second time.
    ///
    /// The state machine arms us while the golfer stands settled over the ball,
    /// so a neighbour's strike in exactly that moment is honoured and reaches
    /// the segmenter. Here it arrives as a golfer who had not moved: no swing
    /// to find, and a report rather than a wrong answer.
    func testRejectsAStrikeWhileTheGolferIsStillAtAddress() {
        var script = SwingFixture.Script()
        script.takeaway = 10.0
        script.trackEnd = 2.0
        let track = SwingFixture.track(script: script)

        XCTAssertThrowsError(try segmenter.segment(track: track, impact: 1.5)) { error in
            XCTAssertEqual(error as? SegmentationFailure, .couldNotLocateTop)
        }
    }

    /// A golfer who never pauses at the top still has a furthest point, which is
    /// why the top is found as a reversal rather than as a stillness.
    func testFindsTheTopWithNoPauseAtAll() throws {
        var script = SwingFixture.Script()
        script.topStart = 1.78
        script.topEnd = 1.78
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)

        XCTAssertEqual(result.top, 1.78, accuracy: 0.08)
        XCTAssertTrue(result.isMonotonic)
    }
}
