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
    case couldNotLocateTop
    case couldNotLocateTakeaway
    case couldNotLocateAddress
    case couldNotLocateFinish
    case nonMonotonicResult
}

public struct SwingSegmenterConfiguration: Sendable {
    /// Below this hand speed (torso-lengths per second) we call the golfer still.
    public var stillSpeed: Double = 0.35
    /// How long stillness must hold to count as an address or a finish.
    public var minStillDuration: Double = 0.18
    /// How far back before impact we are willing to look for the top.
    public var maxBackswingLookback: Double = 3.0
    /// How far past impact we are willing to look for the finish.
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
        let series = track.handSpeedSeries(minimumConfidence: configuration.minimumConfidence)
        guard series.count >= 8 else { throw SegmentationFailure.insufficientSamples }
        guard let first = series.first, let last = series.last,
              impact >= first.time, impact <= last.time else {
            throw SegmentationFailure.impactOutsideTrack
        }

        let impactIndex = nearestIndex(in: series, to: impact)
        let still = configuration.stillSpeed

        // Top of the backswing: walking back from impact, the hands are fast the
        // whole way down, so the first slow sample we meet is the top.
        let backswingFloor = series[impactIndex].time - configuration.maxBackswingLookback
        var index = impactIndex
        while index > 0, series[index].speed > still, series[index].time >= backswingFloor {
            index -= 1
        }
        guard series[index].speed <= still, series[index].time >= backswingFloor else {
            throw SegmentationFailure.couldNotLocateTop
        }
        let topIndex = index

        // Step back off the top's brief stillness, then back through the
        // backswing itself; the next slow sample is the moment motion began.
        while index > 0, series[index].speed <= still {
            index -= 1
        }
        while index > 0, series[index].speed > still, series[index].time >= backswingFloor {
            index -= 1
        }
        guard series[index].speed <= still else {
            throw SegmentationFailure.couldNotLocateTakeaway
        }
        let takeawayIndex = index

        // Address: the start of the settled run that precedes the takeaway.
        while index > 0, series[index - 1].speed <= still {
            index -= 1
        }
        let addressIndex = index
        let addressHeld = series[takeawayIndex].time - series[addressIndex].time
        guard addressHeld >= configuration.minStillDuration || addressIndex == 0 else {
            throw SegmentationFailure.couldNotLocateAddress
        }

        guard let finishIndex = locateFinish(in: series, from: impactIndex) else {
            throw SegmentationFailure.couldNotLocateFinish
        }

        let result = SwingSegmentation(
            address: series[addressIndex].time,
            takeaway: series[takeawayIndex].time,
            top: series[topIndex].time,
            impact: impact,
            finish: series[finishIndex].time
        )
        guard result.isMonotonic else { throw SegmentationFailure.nonMonotonicResult }
        return result
    }

    /// The first sample after impact that begins a settled run.
    ///
    /// A run counts if it holds for `minStillDuration`, or if it simply runs to
    /// the end of the track — a golfer holding their finish as the buffer ends is
    /// the normal case, not a failure.
    private func locateFinish(in series: [SpeedSample], from impactIndex: Int) -> Int? {
        let ceiling = series[impactIndex].time + configuration.maxFinishLookahead
        var candidate = impactIndex + 1

        while candidate < series.count, series[candidate].time <= ceiling {
            guard series[candidate].speed <= configuration.stillSpeed else {
                candidate += 1
                continue
            }
            var end = candidate
            while end + 1 < series.count, series[end + 1].speed <= configuration.stillSpeed {
                end += 1
            }
            let held = series[end].time - series[candidate].time
            if held >= configuration.minStillDuration || end == series.count - 1 {
                return candidate
            }
            candidate = end + 1
        }
        return nil
    }

    private func nearestIndex(in series: [SpeedSample], to time: Timestamp) -> Int {
        var best = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (index, sample) in series.enumerated() {
            let delta = abs(sample.time - time)
            if delta < bestDelta {
                bestDelta = delta
                best = index
            }
        }
        return best
    }
}
