import Foundation

/// Seconds on the capture clock, shared by audio and video.
///
/// The capture session hands audio and video a common clock, which is what lets
/// an impact heard on the microphone name an exact video frame. Keeping that as
/// a bare `Double` keeps CoreMedia out of the core.
public typealias Timestamp = Double

/// A point in normalised image space: `(0, 0)` top-left, `(1, 1)` bottom-right.
public struct Point: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func midpoint(_ a: Point, _ b: Point) -> Point {
        Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// The joints we need. A deliberate subset of what Vision reports — anything we
/// do not use in a metric is noise we would have to keep confidence-checking.
public enum Joint: String, Sendable, CaseIterable, Codable {
    case nose
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

public struct JointReading: Sendable, Equatable, Codable {
    public var position: Point
    public var confidence: Double

    public init(position: Point, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}
