import Foundation

/// A fixed-duration, time-indexed buffer of whatever the caller is holding.
///
/// This is the shape of the capture path: you cannot ask a golfer to press
/// record, because by the time anything triggers, the swing is over. So encoded
/// frames stream into a rolling window continuously and we reach *backwards*
/// into it once we know a swing happened. Nothing reaches disk until then.
///
/// Generic over its element so the core stays free of CoreMedia — the app stores
/// `CMSampleBuffer`s here; the tests store integers.
public struct TimedRingBuffer<Element>: Sendable where Element: Sendable {
    public struct Entry: Sendable {
        public let time: Timestamp
        public let element: Element

        public init(time: Timestamp, element: Element) {
            self.time = time
            self.element = element
        }
    }

    /// How much history to keep, in seconds.
    public let window: Double
    private var entries: [Entry] = []

    public init(window: Double) {
        precondition(window > 0, "A ring buffer needs a positive window")
        self.window = window
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public var span: ClosedRange<Timestamp>? {
        guard let first = entries.first, let last = entries.last else { return nil }
        return first.time...last.time
    }

    /// Appends an entry and evicts anything that has fallen out of the window.
    ///
    /// Out-of-order arrivals are dropped rather than inserted: sample buffers
    /// come off one capture queue in order, and an insert here would be a silent
    /// O(n) cost on the hot path at 240 fps.
    public mutating func append(_ element: Element, at time: Timestamp) {
        if let last = entries.last, time < last.time { return }
        entries.append(Entry(time: time, element: element))
        evict(before: time - window)
    }

    private mutating func evict(before cutoff: Timestamp) {
        guard let firstKept = entries.firstIndex(where: { $0.time >= cutoff }) else {
            entries.removeAll(keepingCapacity: true)
            return
        }
        if firstKept > 0 {
            entries.removeFirst(firstKept)
        }
    }

    /// Everything held within `range`, in order.
    public func entries(in range: ClosedRange<Timestamp>) -> [Entry] {
        entries.filter { range.contains($0.time) }
    }

    public func elements(in range: ClosedRange<Timestamp>) -> [Element] {
        entries(in: range).map(\.element)
    }

    /// Whether the buffer actually holds the whole of `range`.
    ///
    /// Worth checking before trusting a harvested clip: if the swing began
    /// before the oldest frame we still hold, the clip is truncated and the
    /// segmenter will be working from a partial address position.
    public func covers(_ range: ClosedRange<Timestamp>) -> Bool {
        guard let span else { return false }
        return span.lowerBound <= range.lowerBound && span.upperBound >= range.upperBound
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }
}
