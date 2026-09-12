import XCTest
@testable import SwingCore

final class SwingSegmenterTests: XCTestCase {
    private let segmenter = SwingSegmenter()

    func testLocatesEveryKeyMomentOfAScriptedSwing() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.05)
        // Walking back from impact, the first settled sample is the far end of
        // the pause at the top.
        XCTAssertEqual(result.top, script.topEnd, accuracy: 0.05)
        XCTAssertEqual(result.impact, script.impact, accuracy: 0.001)
        XCTAssertEqual(result.finish, script.followThroughEnd, accuracy: 0.06)
        XCTAssertTrue(result.isMonotonic)
    }

    func testTempoRatioMatchesTheScriptedSwing() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)
        let ratio = try XCTUnwrap(result.tempoRatio)

        // 0.80 s back, 0.25 s down — a shade over the 3:1 golfers quote.
        XCTAssertEqual(ratio, 3.2, accuracy: 0.3)
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

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.08)
        XCTAssertEqual(result.top, script.topEnd, accuracy: 0.08)
        XCTAssertTrue(result.isMonotonic)
    }

    func testHandlesASlowerSwing() throws {
        var script = SwingFixture.Script()
        script.topStart = 2.25
        script.topEnd = 2.30
        script.impact = 2.70
        script.followThroughEnd = 3.20
        script.trackEnd = 4.00
        let track = SwingFixture.track(script: script)

        let result = try segmenter.segment(track: track, impact: script.impact)

        XCTAssertEqual(result.takeaway, script.takeaway, accuracy: 0.06)
        XCTAssertEqual(result.top, script.topEnd, accuracy: 0.06)
        XCTAssertTrue(result.isMonotonic)
    }
}
