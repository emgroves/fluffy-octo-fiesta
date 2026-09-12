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

    /// The path the hands travelled.
    ///
    /// We track the hands rather than the club because a clubhead at 100 mph is
    /// a motion-blurred streak no off-the-shelf detector will follow. The hands
    /// are slower, always visible, and their path carries the phase information
    /// the segmenter needs.
    public func handPathSeries(minimumConfidence: Double = 0.3) -> [HandSample] {
        samples.compactMap { sample in
            guard let hand = sample.handPosition(minimumConfidence: minimumConfidence) else {
                return nil
            }
            return HandSample(time: sample.time, position: hand)
        }
    }

    /// How still the hands were around each moment, in torso lengths.
    ///
    /// A window holding fewer than three samples reports `.infinity` — unknown
    /// reads as moving, so a gap in the pose track can never be mistaken for a
    /// golfer standing still.
    public func stillnessSeries(
        window: Double = 0.15,
        alignment: StillnessAlignment = .trailing,
        minimumConfidence: Double = 0.3
    ) -> [StillnessSample] {
        let path = handPathSeries(minimumConfidence: minimumConfidence)
        guard let scale = referenceTorsoLength(minimumConfidence: minimumConfidence),
              scale > 0, !path.isEmpty else { return [] }

        return path.map { sample in
            let span: ClosedRange<Timestamp>
            switch alignment {
            case .trailing: span = (sample.time - window)...sample.time
            case .leading: span = sample.time...(sample.time + window)
            }

            let inWindow = path.filter { span.contains($0.time) }.map(\.position)
            guard inWindow.count >= 3 else {
                return StillnessSample(time: sample.time, spread: .infinity)
            }

            let centroid = Point(
                x: inWindow.reduce(0) { $0 + $1.x } / Double(inWindow.count),
                y: inWindow.reduce(0) { $0 + $1.y } / Double(inWindow.count)
            )
            let spread = inWindow.map { $0.distance(to: centroid) }.max() ?? 0
            return StillnessSample(time: sample.time, spread: spread / scale)
        }
    }
}
