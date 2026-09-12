import Foundation

/// A detected ball strike.
public struct ImpactOnset: Sendable, Equatable {
    public let time: Timestamp
    public let peakLevel: Double
    public let backgroundLevel: Double

    public init(time: Timestamp, peakLevel: Double, backgroundLevel: Double) {
        self.time = time
        self.peakLevel = peakLevel
        self.backgroundLevel = backgroundLevel
    }

    /// How far the strike stood above the ambient bed. A clean strike from the
    /// golfer at the phone is tens of times the background; a neighbour two bays
    /// away is a few times it, which is how we tell them apart.
    public var prominence: Double {
        peakLevel / max(backgroundLevel, 1e-9)
    }
}

public struct ImpactDetectorConfiguration: Sendable {
    public var sampleRate: Double = 48_000
    /// Samples per envelope step. 128 @ 48 kHz is 2.7 ms — finer than one frame
    /// at 240 fps, so the reported time can name an exact video frame.
    public var hopSize: Int = 128
    /// Strike energy is broadband and bright; wind and traffic are not.
    public var highPassCutoff: Double = 900
    /// Multiple of the running background that counts as a strike.
    public var triggerRatio: Double = 6.0
    /// Multiple of the background at which we consider the burst over.
    public var releaseRatio: Double = 2.0
    /// Absolute level a strike must clear regardless of how quiet it is, so that
    /// near-silence cannot make a cough look like a six iron.
    public var absoluteFloor: Double = 0.02
    /// How long to ignore further onsets after one fires. A strike plus its early
    /// reflections is one event, not four.
    public var refractory: Double = 0.45
    /// How fast the background estimate follows the ambient level.
    public var backgroundHalfLife: Double = 0.35
    /// A strike is over quickly; anything longer is a truck going past.
    public var maxBurstDuration: Double = 0.08

    public init() {}
}

/// Streaming detector for the sound of a golf ball being struck.
///
/// The microphone is the best swing trigger available and most apps ignore it.
/// A struck ball is a sharp broadband transient — far cleaner than anything in
/// the video — and because audio and video share a capture clock, the time this
/// reports names a video frame directly. It also filters practice swings for
/// free: a practice swing makes no strike sound.
///
/// This is deliberately not a classifier. It answers "something was struck, and
/// exactly when"; whether it was *this golfer* is decided by pairing it with the
/// pose gate in `SwingStateMachine`.
public final class ImpactOnsetDetector {
    private let configuration: ImpactDetectorConfiguration
    private let hopDuration: Double
    private let highPassCoefficient: Double
    private let backgroundCoefficient: Double

    private var lastInput: Double = 0
    private var lastOutput: Double = 0
    private var hopEnergy: Double = 0
    private var hopSamples: Int = 0
    private var background: Double = 0
    private var primed = false

    private enum State {
        case listening
        case burst(peak: Double, peakTime: Timestamp, started: Timestamp, floor: Double)
        case refractory(until: Timestamp)
    }
    private var state: State = .listening

    public init(configuration: ImpactDetectorConfiguration = ImpactDetectorConfiguration()) {
        self.configuration = configuration
        self.hopDuration = Double(configuration.hopSize) / configuration.sampleRate

        // One-pole high pass: y[n] = a * (y[n-1] + x[n] - x[n-1])
        let dt = 1.0 / configuration.sampleRate
        let rc = 1.0 / (2.0 * Double.pi * configuration.highPassCutoff)
        self.highPassCoefficient = rc / (rc + dt)

        self.backgroundCoefficient = pow(0.5, hopDuration / configuration.backgroundHalfLife)
    }

    public func reset() {
        lastInput = 0
        lastOutput = 0
        hopEnergy = 0
        hopSamples = 0
        background = 0
        primed = false
        state = .listening
    }

    /// Feeds one buffer of mono samples and returns any strikes it completed.
    ///
    /// `startTime` is the capture-clock time of the buffer's first sample. The
    /// clock is re-seeded from it on every call so long sessions cannot drift.
    public func process(_ samples: [Float], startTime: Timestamp) -> [ImpactOnset] {
        var onsets: [ImpactOnset] = []
        let sampleDuration = 1.0 / configuration.sampleRate
        var clock = startTime

        for raw in samples {
            let x = Double(raw)
            let y = highPassCoefficient * (lastOutput + x - lastInput)
            lastOutput = y
            lastInput = x

            hopEnergy += y * y
            hopSamples += 1
            clock += sampleDuration

            if hopSamples >= configuration.hopSize {
                let level = (hopEnergy / Double(hopSamples)).squareRoot()
                hopEnergy = 0
                hopSamples = 0
                if let onset = step(level: level, at: clock) {
                    onsets.append(onset)
                }
            }
        }
        return onsets
    }

    private func step(level: Double, at time: Timestamp) -> ImpactOnset? {
        if !primed {
            background = level
            primed = true
        }

        switch state {
        case .refractory(let until):
            if time >= until {
                state = .listening
            }
            // The background keeps tracking through the refractory window so a
            // change in ambience is not held stale by a burst.
            trackBackground(level)
            return nil

        case .listening:
            let trigger = max(background * configuration.triggerRatio, configuration.absoluteFloor)
            if level >= trigger {
                state = .burst(peak: level, peakTime: time, started: time, floor: background)
            } else {
                trackBackground(level)
            }
            return nil

        case .burst(let peak, let peakTime, let started, let floor):
            var newPeak = peak
            var newPeakTime = peakTime
            if level > peak {
                newPeak = level
                newPeakTime = time
            }

            let release = max(floor * configuration.releaseRatio, configuration.absoluteFloor * 0.5)
            let overran = (time - started) >= configuration.maxBurstDuration

            if level < release || overran {
                state = .refractory(until: newPeakTime + configuration.refractory)
                return ImpactOnset(
                    time: newPeakTime,
                    peakLevel: newPeak,
                    backgroundLevel: floor
                )
            }

            state = .burst(peak: newPeak, peakTime: newPeakTime, started: started, floor: floor)
            return nil
        }
    }

    private func trackBackground(_ level: Double) {
        background = backgroundCoefficient * background + (1 - backgroundCoefficient) * level
    }
}
