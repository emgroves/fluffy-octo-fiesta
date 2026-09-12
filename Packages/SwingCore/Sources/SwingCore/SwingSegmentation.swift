import Foundation

/// The five moments that define a swing, on the capture clock.
public struct SwingSegmentation: Sendable, Equatable {
    public let address: Timestamp
    public let takeaway: Timestamp
    public let top: Timestamp
    public let impact: Timestamp
    public let finish: Timestamp

    public init(
        address: Timestamp,
        takeaway: Timestamp,
        top: Timestamp,
        impact: Timestamp,
        finish: Timestamp
    ) {
        self.address = address
        self.takeaway = takeaway
        self.top = top
        self.impact = impact
        self.finish = finish
    }

    public var backswingDuration: Double { top - takeaway }
    public var downswingDuration: Double { impact - top }
    public var totalDuration: Double { finish - address }

    /// Backswing divided by downswing — the number a golfer already knows, where
    /// tour players cluster near 3:1. Returns `nil` rather than a wild figure
    /// when the downswing is too short to divide by meaningfully.
    public var tempoRatio: Double? {
        guard downswingDuration > 0.01 else { return nil }
        return backswingDuration / downswingDuration
    }

    /// The span to keep on disk, padded so the clip does not start or end abruptly.
    public func clipRange(leadIn: Double = 0.3, leadOut: Double = 0.5) -> ClosedRange<Timestamp> {
        (address - leadIn)...(finish + leadOut)
    }

    /// True when the moments are in the order physics requires.
    public var isMonotonic: Bool {
        address <= takeaway && takeaway <= top && top <= impact && impact <= finish
    }
}

public enum SegmentationFailure: Error, Sendable, Equatable {
    case insufficientSamples
    case impactOutsideTrack
    case couldNotLocateTakeaway
    case couldNotLocateAddress
    case couldNotLocateTop
    case couldNotLocateFinish
    case nonMonotonicResult
}

public struct SwingSegmenterConfiguration: Sendable {
    /// How much history a stillness measurement looks over.
    public var stillWindow: Double = 0.15
    /// Hand spread within that window, in torso lengths, that still counts as
    /// settled. A still golfer measures around 0.03 with realistic pose jitter;
    /// mid-backswing measures around 0.15.
    ///
    /// This wants calibrating against real footage — a golfer who waggles will
    /// sit higher than one who sets and freezes, and that is what the fixture
    /// corpus in the plan (§9) is for.
    public var stillRadius: Double = 0.07
    /// How long stillness must hold to count as an address or a finish.
    public var minStillDuration: Double = 0.18
    public var maxBackswingLookback: Double = 3.0
    public var maxFinishLookahead: Double = 2.5
    public var minimumConfidence: Double = 0.3

    public init() {}
}

/// Turns a pose track plus a known impact time into the five key moments.
///
/// The impact time comes from the microphone, not from here — see
/// `ImpactOnsetDetector`. Being handed impact rather than having to find it is
/// what makes this tractable: every other moment is located by walking outward
/// from a point we already trust.
public struct SwingSegmenter: Sendable {
    public var configuration: SwingSegmenterConfiguration

    public init(configuration: SwingSegmenterConfiguration = SwingSegmenterConfiguration()) {
        self.configuration = configuration
    }

    public func segment(track: PoseTrack, impact: Timestamp) throws -> SwingSegmentation {
        let path = track.handPathSeries(minimumConfidence: configuration.minimumConfidence)
        guard path.count >= 8 else { throw SegmentationFailure.insufficientSamples }
        guard let first = path.first, let last = path.last,
              impact >= first.time, impact <= last.time else {
            throw SegmentationFailure.impactOutsideTrack
        }

        let trailing = track.stillnessSeries(
            window: configuration.stillWindow,
            alignment: .trailing,
            minimumConfidence: configuration.minimumConfidence
        )
        let leading = track.stillnessSeries(
            window: configuration.stillWindow,
            alignment: .leading,
            minimumConfidence: configuration.minimumConfidence
        )
        guard trailing.count == path.count, leading.count == path.count else {
            throw SegmentationFailure.insufficientSamples
        }

        let impactIndex = nearestIndex(in: path, to: impact)
        let radius = configuration.stillRadius

        // Takeaway: walking back from impact, the hands are moving the whole way
        // — up and then down — so the first settled sample we meet is the last
        // moment before the swing started. A trailing window is essential here:
        // it stays settled right up to the instant motion begins.
        let floor = path[impactIndex].time - configuration.maxBackswingLookback
        var index = impactIndex
        while index > 0, trailing[index].spread > radius, path[index].time >= floor {
            index -= 1
        }
        guard trailing[index].spread <= radius, path[index].time >= floor else {
            throw SegmentationFailure.couldNotLocateTakeaway
        }
        let takeawayIndex = index

        // Address: the start of the settled run that precedes it. The trailing
        // window only reports settled once it has filled, so the golfer actually
        // came to rest one window earlier than the run appears to start.
        while index > 0, trailing[index - 1].spread <= radius {
            index -= 1
        }
        let runStart = path[index].time
        let held = path[takeawayIndex].time - runStart + configuration.stillWindow
        guard held >= configuration.minStillDuration || index == 0 else {
            throw SegmentationFailure.couldNotLocateAddress
        }
        let address = max(path[0].time, runStart - configuration.stillWindow)

        // Top of the backswing: the moment the hands sit furthest from where
        // they started. A reversal, not a stillness — a golfer with no pause at
        // the top still has a furthest point, and looking for one avoids
        // thresholding a derivative anywhere in this function.
        let addressPosition = path[takeawayIndex].position
        var topIndex = takeawayIndex
        var furthest = -1.0
        for candidate in (takeawayIndex + 1)...impactIndex {
            let distance = path[candidate].position.distance(to: addressPosition)
            if distance > furthest {
                furthest = distance
                topIndex = candidate
            }
        }
        guard furthest > 0 else { throw SegmentationFailure.couldNotLocateTop }

        guard let finishIndex = locateFinish(
            path: path, leading: leading, from: impactIndex
        ) else {
            throw SegmentationFailure.couldNotLocateFinish
        }

        let result = SwingSegmentation(
            address: address,
            takeaway: path[takeawayIndex].time,
            top: path[topIndex].time,
            impact: impact,
            finish: path[finishIndex].time
        )
        guard result.isMonotonic else { throw SegmentationFailure.nonMonotonicResult }
        return result
    }

    /// The first moment after impact from which the hands stay settled.
    ///
    /// A run counts if it holds for `minStillDuration`, or if it simply runs to
    /// the end of the track — a golfer holding their finish as the buffer ends is
    /// the normal case, not a failure.
    private func locateFinish(
        path: [HandSample],
        leading: [StillnessSample],
        from impactIndex: Int
    ) -> Int? {
        let ceiling = path[impactIndex].time + configuration.maxFinishLookahead
        var candidate = impactIndex + 1

        while candidate < path.count, path[candidate].time <= ceiling {
            guard leading[candidate].spread <= configuration.stillRadius else {
                candidate += 1
                continue
            }
            var end = candidate
            while end + 1 < path.count, leading[end + 1].spread <= configuration.stillRadius {
                end += 1
            }
            let held = path[end].time - path[candidate].time + configuration.stillWindow
            if held >= configuration.minStillDuration || end == path.count - 1 {
                return candidate
            }
            candidate = end + 1
        }
        return nil
    }

    private func nearestIndex(in path: [HandSample], to time: Timestamp) -> Int {
        var best = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (index, sample) in path.enumerated() {
            let delta = abs(sample.time - time)
            if delta < bestDelta {
                bestDelta = delta
                best = index
            }
        }
        return best
    }
}
