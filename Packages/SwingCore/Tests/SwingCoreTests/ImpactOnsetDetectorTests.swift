import XCTest
@testable import SwingCore

final class ImpactOnsetDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testFindsASingleStrikeAtTheRightMoment() {
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: [1.0]
        )

        let onsets = detector.process(audio, startTime: 0)

        XCTAssertEqual(onsets.count, 1)
        // The whole point of the audio trigger is sub-frame accuracy: at 240 fps
        // one frame is 4.2 ms, and we claim to land inside a couple of them.
        XCTAssertEqual(onsets.first?.time ?? 0, 1.0, accuracy: 0.01)
    }

    func testIgnoresAQuietRange() {
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: []
        )

        XCTAssertTrue(detector.process(audio, startTime: 0).isEmpty)
    }

    func testRefractoryPeriodCollapsesEchoesIntoOneStrike() {
        let detector = ImpactOnsetDetector()
        // A strike plus a reflection off the bay divider is one event.
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: [1.0, 1.06]
        )

        XCTAssertEqual(detector.process(audio, startTime: 0).count, 1)
    }

    func testSeparateStrikesAreReportedSeparately() {
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 3.0, sampleRate: sampleRate, strikesAt: [1.0, 2.0]
        )

        let onsets = detector.process(audio, startTime: 0)

        XCTAssertEqual(onsets.count, 2)
        XCTAssertEqual(onsets.first?.time ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(onsets.last?.time ?? 0, 2.0, accuracy: 0.01)
    }

    func testTimestampsAreContinuousAcrossBufferBoundaries() {
        // Audio arrives in buffers; a strike that straddles two of them must not
        // land at the wrong time or be reported twice.
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: [1.0]
        )
        let chunk = 1024

        var onsets: [ImpactOnset] = []
        var offset = 0
        while offset < audio.count {
            let end = min(offset + chunk, audio.count)
            let slice = Array(audio[offset..<end])
            onsets += detector.process(slice, startTime: Double(offset) / sampleRate)
            offset = end
        }

        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(onsets.first?.time ?? 0, 1.0, accuracy: 0.01)
    }

    func testProminenceSeparatesAStrikeFromTheAmbientBed() {
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: [1.0]
        )

        let onset = detector.process(audio, startTime: 0).first

        XCTAssertNotNil(onset)
        // Prominence is what will eventually let us rank our own strike above a
        // neighbouring bay's, so it needs to be a large number, not a marginal one.
        XCTAssertGreaterThan(onset?.prominence ?? 0, 10)
    }

    func testResetClearsDetectorState() {
        let detector = ImpactOnsetDetector()
        let audio = AudioFixture.range(
            duration: 2.0, sampleRate: sampleRate, strikesAt: [1.0]
        )

        _ = detector.process(audio, startTime: 0)
        detector.reset()
        let second = detector.process(audio, startTime: 0)

        XCTAssertEqual(second.count, 1, "A reset detector should behave like a new one")
    }
}
