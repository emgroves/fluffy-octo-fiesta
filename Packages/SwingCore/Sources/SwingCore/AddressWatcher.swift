import Foundation

public enum AddressEvent: Sendable, Equatable {
    case held
    case broken
}

/// Decides when a golfer has settled over the ball.
///
/// This is the vision half of the trigger. The microphone will hear every strike
/// on the range; arming only once *this* golfer has stood still over a ball is
/// what makes the loud noise attributable. Requiring the stillness to hold for a
/// beat also keeps someone walking past from arming us.
///
/// Streaming counterpart to `PoseTrack.stillnessSeries` — same measurement, but
/// over a trailing window it maintains itself, because live there is no future
/// to look at.
public struct AddressWatcher: Sendable {
    public struct Configuration: Sendable {
        /// How much history the stillness measurement looks over.
        public var window: Double = 0.15
        /// Hand spread within that window, in torso lengths, that counts as settled.
        public var stillRadius: Double = 0.07
        /// How long that has to hold before we arm.
        public var holdDuration: Double = 0.6

        public init() {}
    }

    public var configuration: Configuration
    public private(set) var isAtAddress = false
    private var recent: [HandSample] = []
    private var stillSince: Timestamp?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one observation of the hands. Returns an event only on a change.
    ///
    /// `torsoLength` scales the measurement so the same threshold works whether
    /// the phone is six feet away or twelve.
    public mutating func update(
        hand: Point,
        torsoLength: Double,
        at time: Timestamp
    ) -> AddressEvent? {
        guard torsoLength > 0 else { return nil }

        recent.append(HandSample(time: time, position: hand))
        let cutoff = time - configuration.window
        if let firstKept = recent.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            recent.removeFirst(firstKept)
        }

        // Until the window has filled we know nothing, and guessing here would
        // arm us on the first frame a golfer walks into shot.
        guard recent.count >= 3,
              let oldest = recent.first,
              time - oldest.time >= configuration.window * 0.8 else { return nil }

        let centroid = Point(
            x: recent.reduce(0) { $0 + $1.position.x } / Double(recent.count),
            y: recent.reduce(0) { $0 + $1.position.y } / Double(recent.count)
        )
        let spread = (recent.map { $0.position.distance(to: centroid) }.max() ?? 0) / torsoLength

        guard spread <= configuration.stillRadius else {
            stillSince = nil
            guard isAtAddress else { return nil }
            isAtAddress = false
            return .broken
        }

        let since = stillSince ?? time
        stillSince = since

        guard !isAtAddress, time - since >= configuration.holdDuration else { return nil }
        isAtAddress = true
        return .held
    }

    public mutating func reset() {
        isAtAddress = false
        stillSince = nil
        recent.removeAll()
    }
}
