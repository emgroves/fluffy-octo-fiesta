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
public struct AddressWatcher: Sendable {
    public struct Configuration: Sendable {
        /// Hand speed below which we call the golfer still, in torso-lengths/sec.
        public var stillSpeed: Double = 0.35
        /// How long that has to hold before we arm.
        public var holdDuration: Double = 0.6

        public init() {}
    }

    public var configuration: Configuration
    public private(set) var isAtAddress = false
    private var stillSince: Timestamp?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one hand-speed reading. Returns an event only when the state changes.
    public mutating func update(speed: Double, at time: Timestamp) -> AddressEvent? {
        guard speed <= configuration.stillSpeed else {
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
    }
}
