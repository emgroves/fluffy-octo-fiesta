import Foundation

/// A time-ordered run of pose samples.
public struct PoseTrack: Sendable, Equatable {
    public private(set) var samples: [PoseSample]

    public init(samples: [PoseSample] = []) {
        self.samples = samples.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var count: Int { samples.count }

    public var timeRange: ClosedRange<Timestamp>? {
        guard let first = samples.first, let last = samples.last, first.time <= last.time else {
            return nil
        }
        return first.time...last.time
    }

    /// Appends a sample, keeping the track sorted.
    ///
    /// Vision results can arrive slightly out of order when requests are served
    /// off more than one queue, so we insert rather than assume.
    public mutating func append(_ sample: PoseSample) {
        if let last = samples.last, last.time <= sample.time {
            samples.append(sample)
        } else {
            let index = samples.firstIndex { $0.time > sample.time } ?? samples.endIndex
            samples.insert(sample, at: index)
        }
    }

    /// Drops everything older than `horizon` seconds before the newest sample.
    public mutating func trim(toTrailing horizon: Double) {
        guard let newest = samples.last?.time else { return }
        let cutoff = newest - horizon
        guard let firstKept = samples.firstIndex(where: { $0.time >= cutoff }) else {
            samples.removeAll()
            return
        }
        if firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    /// The characteristic torso length for this track, in normalised units.
    ///
    /// Taken as a median across samples so that a few frames of bad pose — a
    /// crossed arm, a moment of occlusion — cannot rescale every metric.
    public func referenceTorsoLength(minimumConfidence: Double = 0.3) -> Double? {
        let lengths = samples
            .compactMap { $0.torsoLength(minimumConfidence: minimumConfidence) }
            .sorted()
        guard !lengths.isEmpty else { return nil }
        return lengths[lengths.count / 2]
    }

    /// Hand speed over time, in torso-lengths per second.
    ///
    /// This one series drives the whole segmenter: the address and the finish are
    /// where it sits near zero, the top of the backswing is where it dips back to
    /// zero between two bursts of motion.
    public func handSpeedSeries(minimumConfidence: Double = 0.3) -> [SpeedSample] {
        guard let scale = referenceTorsoLength(minimumConfidence: minimumConfidence) else {
            return []
        }

        var series: [SpeedSample] = []
        series.reserveCapacity(samples.count)

        var previous: (time: Timestamp, point: Point)?
        for sample in samples {
            guard let hand = sample.handPosition(minimumConfidence: minimumConfidence) else {
                // A dropped frame breaks the chain rather than producing a bogus
                // spike across the gap.
                previous = nil
                continue
            }
            defer { previous = (sample.time, hand) }
            guard let last = previous else { continue }
            let dt = sample.time - last.time
            guard dt > 0 else { continue }
            let speed = last.point.distance(to: hand) / (dt * scale)
            series.append(SpeedSample(time: sample.time, speed: speed))
        }
        return series
    }
}

public struct SpeedSample: Sendable, Equatable {
    public var time: Timestamp
    /// Torso-lengths per second.
    public var speed: Double

    public init(time: Timestamp, speed: Double) {
        self.time = time
        self.speed = speed
    }
}
