import Foundation

/// The Tier A metrics — the ones a single 2D camera can stand behind.
///
/// Deliberately absent: clubhead speed, ball speed, launch angle, face angle.
/// Those need radar or calibrated stereo high-speed capture, and a golfer with a
/// launch monitor will catch an estimate immediately.
public struct SwingMetrics: Sendable, Equatable {
    public let backswingDuration: Double
    public let downswingDuration: Double
    public let totalDuration: Double
    /// Backswing : downswing. Tour players cluster near 3.0.
    public let tempoRatio: Double?
    /// Greatest head displacement between address and impact, in torso-lengths.
    public let headDrift: Double?
    /// Change in spine lean between address and impact, in degrees. Down-the-line
    /// framing only — from face-on it measures nothing meaningful.
    public let spineAngleChange: Double?

    public init(
        backswingDuration: Double,
        downswingDuration: Double,
        totalDuration: Double,
        tempoRatio: Double?,
        headDrift: Double?,
        spineAngleChange: Double?
    ) {
        self.backswingDuration = backswingDuration
        self.downswingDuration = downswingDuration
        self.totalDuration = totalDuration
        self.tempoRatio = tempoRatio
        self.headDrift = headDrift
        self.spineAngleChange = spineAngleChange
    }
}

public enum SwingMetricsCalculator {
    public static func metrics(
        track: PoseTrack,
        segmentation: SwingSegmentation,
        minimumConfidence: Double = 0.3
    ) -> SwingMetrics {
        SwingMetrics(
            backswingDuration: segmentation.backswingDuration,
            downswingDuration: segmentation.downswingDuration,
            totalDuration: segmentation.totalDuration,
            tempoRatio: segmentation.tempoRatio,
            headDrift: headDrift(
                track: track,
                from: segmentation.address,
                to: segmentation.impact,
                minimumConfidence: minimumConfidence
            ),
            spineAngleChange: spineAngleChange(
                track: track,
                at: segmentation.address,
                and: segmentation.impact,
                minimumConfidence: minimumConfidence
            )
        )
    }

    static func headDrift(
        track: PoseTrack,
        from start: Timestamp,
        to end: Timestamp,
        minimumConfidence: Double
    ) -> Double? {
        guard let scale = track.referenceTorsoLength(minimumConfidence: minimumConfidence),
              let anchor = track.samples
                .first(where: { $0.time >= start })?
                .position(.nose, minimumConfidence: minimumConfidence) else { return nil }

        var greatest = 0.0
        for sample in track.samples where sample.time >= start && sample.time <= end {
            guard let head = sample.position(.nose, minimumConfidence: minimumConfidence) else {
                continue
            }
            greatest = max(greatest, anchor.distance(to: head) / scale)
        }
        return greatest
    }

    static func spineAngleChange(
        track: PoseTrack,
        at start: Timestamp,
        and end: Timestamp,
        minimumConfidence: Double
    ) -> Double? {
        guard let a = spineAngle(track: track, at: start, minimumConfidence: minimumConfidence),
              let b = spineAngle(track: track, at: end, minimumConfidence: minimumConfidence) else {
            return nil
        }
        return b - a
    }

    /// Degrees of lean from vertical, measured hips-to-shoulders.
    static func spineAngle(
        track: PoseTrack,
        at time: Timestamp,
        minimumConfidence: Double
    ) -> Double? {
        guard let sample = track.samples.first(where: { $0.time >= time }),
              let shoulders = sample.shoulderMidpoint(minimumConfidence: minimumConfidence),
              let hips = sample.hipMidpoint(minimumConfidence: minimumConfidence) else {
            return nil
        }
        // Image space runs downward, so a golfer's shoulders sit at a smaller y
        // than their hips; flip dy to get a conventional angle.
        let dx = shoulders.x - hips.x
        let dy = hips.y - shoulders.y
        guard dx != 0 || dy != 0 else { return nil }
        return atan2(dx, dy) * 180 / Double.pi
    }
}
