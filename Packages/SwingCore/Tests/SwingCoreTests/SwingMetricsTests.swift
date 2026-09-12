import XCTest
@testable import SwingCore

final class SwingMetricsTests: XCTestCase {
    func testReportsTempoAndDurationsFromTheSegmentation() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script)
        let segmentation = try SwingSegmenter().segment(track: track, impact: script.impact)

        let metrics = SwingMetricsCalculator.metrics(track: track, segmentation: segmentation)

        XCTAssertEqual(metrics.downswingDuration, 0.25, accuracy: 0.06)
        XCTAssertEqual(try XCTUnwrap(metrics.tempoRatio), 3.2, accuracy: 0.3)
        XCTAssertGreaterThan(metrics.totalDuration, 1.0)
    }

    func testSteadyHeadMeasuresAlmostNoDrift() throws {
        let script = SwingFixture.Script()
        let track = SwingFixture.track(script: script, headDriftAtImpact: 0)
        let segmentation = try SwingSegmenter().segment(track: track, impact: script.impact)

        let drift = try XCTUnwrap(
            SwingMetricsCalculator.metrics(track: track, segmentation: segmentation).headDrift
        )

        XCTAssertLessThan(drift, 0.02)
    }

    func testSwayingHeadIsMeasuredInTorsoLengths() throws {
        let script = SwingFixture.Script()
        // Move the head by one fifth of a torso length by impact.
        let sway = SwingFixture.torsoLength * 0.2
        let track = SwingFixture.track(script: script, headDriftAtImpact: sway)
        let segmentation = try SwingSegmenter().segment(track: track, impact: script.impact)

        let drift = try XCTUnwrap(
            SwingMetricsCalculator.metrics(track: track, segmentation: segmentation).headDrift
        )

        XCTAssertEqual(drift, 0.2, accuracy: 0.03)
    }

    func testSpineAngleIsMeasuredFromVertical() throws {
        var readings: [Joint: JointReading] = [:]
        readings[.leftShoulder] = JointReading(position: Point(x: 0.44, y: 0.40), confidence: 1)
        readings[.rightShoulder] = JointReading(position: Point(x: 0.56, y: 0.40), confidence: 1)
        readings[.leftHip] = JointReading(position: Point(x: 0.46, y: 0.60), confidence: 1)
        readings[.rightHip] = JointReading(position: Point(x: 0.54, y: 0.60), confidence: 1)
        let track = PoseTrack(samples: [PoseSample(time: 0, readings: readings)])

        let angle = SwingMetricsCalculator.spineAngle(track: track, at: 0, minimumConfidence: 0.3)

        // Shoulders directly above hips reads as upright.
        XCTAssertEqual(try XCTUnwrap(angle), 0, accuracy: 0.5)
    }

    func testMetricsAreAbsentRatherThanWrongWhenJointsAreMissing() throws {
        // A golfer filmed from behind loses the face; we return nil instead of
        // inventing a head-drift figure.
        let script = SwingFixture.Script()
        var track = PoseTrack()
        for sample in SwingFixture.track(script: script).samples {
            var stripped = sample
            stripped.readings[.nose] = nil
            track.append(stripped)
        }
        let segmentation = try SwingSegmenter().segment(track: track, impact: script.impact)

        let metrics = SwingMetricsCalculator.metrics(track: track, segmentation: segmentation)

        XCTAssertNil(metrics.headDrift)
        XCTAssertNotNil(metrics.tempoRatio, "Tempo does not depend on the face")
    }
}
