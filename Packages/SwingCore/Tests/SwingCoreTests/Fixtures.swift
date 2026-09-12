import Foundation
@testable import SwingCore

/// Deterministic pseudo-random source.
///
/// Tests that feed "noise" to a detector must not flake, so nothing here uses
/// the system RNG.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64 = 0x5DEECE66D) {
        self.state = seed
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = (state >> 11) & ((1 << 53) - 1)
        return Double(bits) / Double(1 << 53)
    }

    /// Uniform in `-amplitude ... amplitude`.
    mutating func noise(amplitude: Double) -> Float {
        Float((next() * 2 - 1) * amplitude)
    }
}

enum AudioFixture {
    /// A quiet bed with sharp bursts at the given times — a stand-in for a range
    /// with a ball being struck.
    static func range(
        duration: Double,
        sampleRate: Double,
        strikesAt strikes: [Double],
        strikeDuration: Double = 0.005,
        strikeAmplitude: Double = 0.5,
        bedAmplitude: Double = 0.001,
        seed: UInt64 = 42
    ) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        let total = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: total)

        for index in 0..<total {
            let time = Double(index) / sampleRate
            let striking = strikes.contains { time >= $0 && time < $0 + strikeDuration }
            samples[index] = generator.noise(amplitude: striking ? strikeAmplitude : bedAmplitude)
        }
        return samples
    }
}

/// Builds a pose track for a scripted swing with known key moments.
enum SwingFixture {
    static let shoulderY = 0.40
    static let hipY = 0.60
    /// Shoulders-to-hips, the scale every metric is expressed in.
    static let torsoLength = 0.20

    struct Script {
        var addressStart = 0.0
        var takeaway = 1.0
        var topStart = 1.75
        var topEnd = 1.80
        var impact = 2.05
        var followThroughEnd = 2.45
        var trackEnd = 3.20

        var addressHands = Point(x: 0.50, y: 0.60)
        var topHands = Point(x: 0.35, y: 0.35)
        var finishHands = Point(x: 0.62, y: 0.34)
    }

    /// A swing at 60 Hz — the rate we decimate pose inference to, not the 240 fps
    /// the video is captured at.
    static func track(
        script: Script = Script(),
        sampleRate: Double = 60,
        headDriftAtImpact: Double = 0,
        confidence: Double = 0.9
    ) -> PoseTrack {
        var track = PoseTrack()
        let step = 1.0 / sampleRate
        var time = script.addressStart

        while time <= script.trackEnd {
            let hands = handPosition(at: time, script: script)
            let progress = min(max((time - script.takeaway) /
                                   max(script.impact - script.takeaway, 1e-6), 0), 1)
            let nose = Point(x: 0.50 + headDriftAtImpact * progress, y: 0.33)

            var readings: [Joint: JointReading] = [:]
            func put(_ joint: Joint, _ point: Point) {
                readings[joint] = JointReading(position: point, confidence: confidence)
            }
            put(.nose, nose)
            put(.leftShoulder, Point(x: 0.44, y: shoulderY))
            put(.rightShoulder, Point(x: 0.56, y: shoulderY))
            put(.leftHip, Point(x: 0.46, y: hipY))
            put(.rightHip, Point(x: 0.54, y: hipY))
            put(.leftWrist, Point(x: hands.x - 0.01, y: hands.y))
            put(.rightWrist, Point(x: hands.x + 0.01, y: hands.y))

            track.append(PoseSample(time: time, readings: readings))
            time += step
        }
        return track
    }

    private static func handPosition(at time: Double, script: Script) -> Point {
        if time < script.takeaway {
            return script.addressHands
        }
        if time < script.topStart {
            return interpolate(
                script.addressHands, script.topHands,
                (time - script.takeaway) / (script.topStart - script.takeaway)
            )
        }
        if time < script.topEnd {
            return script.topHands
        }
        if time < script.impact {
            return interpolate(
                script.topHands, script.addressHands,
                (time - script.topEnd) / (script.impact - script.topEnd)
            )
        }
        if time < script.followThroughEnd {
            return interpolate(
                script.addressHands, script.finishHands,
                (time - script.impact) / (script.followThroughEnd - script.impact)
            )
        }
        return script.finishHands
    }

    private static func interpolate(_ a: Point, _ b: Point, _ t: Double) -> Point {
        let clamped = min(max(t, 0), 1)
        return Point(x: a.x + (b.x - a.x) * clamped, y: a.y + (b.y - a.y) * clamped)
    }
}
