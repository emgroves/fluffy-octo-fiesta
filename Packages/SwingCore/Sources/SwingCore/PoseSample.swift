import Foundation

/// One frame of body pose, timestamped on the capture clock.
public struct PoseSample: Sendable, Equatable, Codable {
    public var time: Timestamp
    public var readings: [Joint: JointReading]

    public init(time: Timestamp, readings: [Joint: JointReading]) {
        self.time = time
        self.readings = readings
    }

    /// The position of a joint, or `nil` if it is missing or too uncertain to use.
    public func position(_ joint: Joint, minimumConfidence: Double = 0.3) -> Point? {
        guard let reading = readings[joint], reading.confidence >= minimumConfidence else {
            return nil
        }
        return reading.position
    }

    public func midpoint(
        _ a: Joint,
        _ b: Joint,
        minimumConfidence: Double = 0.3
    ) -> Point? {
        guard let pa = position(a, minimumConfidence: minimumConfidence),
              let pb = position(b, minimumConfidence: minimumConfidence) else { return nil }
        return Point.midpoint(pa, pb)
    }

    /// Midpoint of the two wrists — our stand-in for "the hands".
    ///
    /// We track the hands rather than the club because a clubhead at 100 mph is a
    /// motion-blurred streak that no off-the-shelf detector will follow reliably.
    /// The hands are slower, always visible, and their speed profile carries the
    /// phase information we actually need.
    public func handPosition(minimumConfidence: Double = 0.3) -> Point? {
        midpoint(.leftWrist, .rightWrist, minimumConfidence: minimumConfidence)
    }

    public func shoulderMidpoint(minimumConfidence: Double = 0.3) -> Point? {
        midpoint(.leftShoulder, .rightShoulder, minimumConfidence: minimumConfidence)
    }

    public func hipMidpoint(minimumConfidence: Double = 0.3) -> Point? {
        midpoint(.leftHip, .rightHip, minimumConfidence: minimumConfidence)
    }

    /// Shoulders-to-hips distance, used to express every other measurement in
    /// body lengths instead of pixels — so a metric means the same thing whether
    /// the phone is six feet away or twelve.
    public func torsoLength(minimumConfidence: Double = 0.3) -> Double? {
        guard let shoulders = shoulderMidpoint(minimumConfidence: minimumConfidence),
              let hips = hipMidpoint(minimumConfidence: minimumConfidence) else { return nil }
        let length = shoulders.distance(to: hips)
        return length > 0 ? length : nil
    }
}
