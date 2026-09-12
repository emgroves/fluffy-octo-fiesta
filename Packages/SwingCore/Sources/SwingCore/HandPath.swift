import Foundation

/// The hands at one moment, in normalised image space.
public struct HandSample: Sendable, Equatable {
    public var time: Timestamp
    public var position: Point

    public init(time: Timestamp, position: Point) {
        self.time = time
        self.position = position
    }
}

/// How still the hands were over a window, in torso lengths.
///
/// Measured as the greatest distance any sample in the window sat from the
/// window's centroid. This replaces frame-to-frame speed, and the reason is
/// arithmetic: differentiating a pose track multiplies position jitter by the
/// inference rate. At 60 Hz, four pixels of Vision jitter on a 1080p frame
/// becomes roughly 0.9 torso-lengths/sec of phantom speed — more than twice any
/// threshold that could separate a still golfer from a moving one. Measuring
/// spread over a window instead leaves a still golfer at ~0.03 and a golfer
/// mid-backswing at ~0.15, which is a gap you can actually threshold.
public struct StillnessSample: Sendable, Equatable {
    public var time: Timestamp
    public var spread: Double

    public init(time: Timestamp, spread: Double) {
        self.time = time
        self.spread = spread
    }
}

/// Which way a stillness window looks from the sample it describes.
///
/// The choice matters at the edges of a swing. A trailing window stays still
/// right up to the instant the takeaway begins; a leading one becomes still at
/// the instant the golfer settles into their finish. Using a centred window for
/// either would report the moment roughly half a window early or late.
public enum StillnessAlignment: Sendable {
    case trailing
    case leading
}
