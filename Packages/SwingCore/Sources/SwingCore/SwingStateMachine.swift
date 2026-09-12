import Foundation

public enum SwingState: Sendable, Equatable {
    case idle
    case framing
    case armed
    case capturing(impact: Timestamp)
    case segmenting(impact: Timestamp)
    case replaying
}

public enum SwingInput: Sendable, Equatable {
    case personAppeared
    case personDisappeared
    case addressHeld
    case addressBroken
    case impactHeard(Timestamp)
    /// Enough footage has accumulated after impact to cover the follow-through.
    case captureWindowElapsed
    case segmentationSucceeded
    case segmentationFailed
    case replayFinished
    case reset
}

public enum SwingEffect: Sendable, Equatable {
    case startPoseTracking
    case stopPoseTracking
    case showFramingGuides
    case showWaitingForAddress
    case harvestClip(impact: Timestamp)
    case startReplay
    case stopReplay
    case returnToLive
}

/// The hands-free loop, as a state machine.
///
/// The important rule lives in one place here: `impactHeard` is only honoured
/// from `.armed`. The microphone knows *when* a ball was struck but not *whose*
/// — on a busy range you hear every bay. Requiring the pose gate to have armed
/// us first is what turns a loud noise into this golfer's swing.
public struct SwingStateMachine: Sendable {
    public private(set) var state: SwingState

    public init(state: SwingState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ input: SwingInput) -> [SwingEffect] {
        switch (state, input) {
        case (_, .reset):
            let wasReplaying = state == .replaying
            state = .idle
            return wasReplaying ? [.stopReplay, .stopPoseTracking] : [.stopPoseTracking]

        case (.idle, .personAppeared):
            state = .framing
            return [.startPoseTracking, .showFramingGuides]

        case (.framing, .addressHeld):
            state = .armed
            return [.showWaitingForAddress]

        case (.framing, .personDisappeared):
            state = .idle
            return [.stopPoseTracking]

        case (.armed, .addressBroken):
            state = .framing
            return [.showFramingGuides]

        case (.armed, .personDisappeared):
            state = .idle
            return [.stopPoseTracking]

        case (.armed, .impactHeard(let time)):
            state = .capturing(impact: time)
            return []

        case (.capturing(let time), .captureWindowElapsed):
            state = .segmenting(impact: time)
            // Pose tracking pauses for the whole replay stretch. It is roughly a
            // third of a range session, and it is the cheapest thermal saving
            // available to us.
            return [.stopPoseTracking, .harvestClip(impact: time)]

        case (.segmenting, .segmentationSucceeded):
            state = .replaying
            return [.startReplay]

        case (.segmenting, .segmentationFailed):
            state = .framing
            return [.startPoseTracking, .returnToLive, .showFramingGuides]

        case (.replaying, .replayFinished):
            state = .framing
            return [.stopReplay, .startPoseTracking, .returnToLive, .showFramingGuides]

        default:
            // Every other pairing is a no-op rather than an error. Pose and audio
            // arrive on separate queues, so late and duplicate inputs are normal
            // traffic, not bugs to trap.
            return []
        }
    }
}
