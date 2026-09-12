import AVFoundation
import Observation
import SwiftUI
import SwingCore

/// Coordinates capture, detection, segmentation and replay.
///
/// Every decision this type makes is delegated to `SwingCore` — the state
/// machine, the address watcher, the segmenter, the metrics. What lives here is
/// only the wiring: AVFoundation in, SwiftUI out. Keeping it that way is what
/// lets the interesting half be tested without a phone.
@MainActor
@Observable
final class SwingSessionModel {
    enum Surface: Equatable {
        case live
        case waiting
        case replay(SwingClip)
    }

    // MARK: Display state

    var golferDisplayEnabled = true
    var golferDisplayAvailable = false
    private(set) var surface: Surface = .live
    private(set) var cameraAngle: CameraAngle = .downTheLine
    private(set) var swings: [SwingClip] = []
    var selectedSwing: SwingClip.ID?

    var captureSession: AVCaptureSession { capture.session }

    var framingHint: String {
        switch machine.state {
        case .idle: "Step into frame"
        case .framing: cameraAngle.guidanceText
        case .armed: "Ready — hit when you are"
        default: ""
        }
    }

    /// One number, not a dashboard. At ten feet in sunlight the golfer gets to
    /// read exactly one thing.
    var headline: String? {
        guard case .replay(let clip) = surface, let ratio = clip.metrics.tempoRatio else {
            return nil
        }
        return String(format: "%.1f : 1", ratio)
    }

    // MARK: Machinery

    private let capture = CaptureController()
    private var machine = SwingStateMachine()
    private var addressWatcher = AddressWatcher()
    private let segmenter = SwingSegmenter()
    private var track = PoseTrack()
    private var frames = TimedRingBuffer<CMSampleBuffer>(window: 8.0)
    private var harvester: ClipHarvester?
    private var poseMonitor: PoseMonitor?
    private var audioMonitor: AudioImpactMonitor?
    private var lastFormat: CMFormatDescription?
    private var captureDeadline: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?

    /// Playback speed on the golfer-facing display, and how many times a swing
    /// loops before the screen hands itself back to live framing.
    private let replayRate = 0.25
    private let replayLoops = 3.0

    /// How long after impact we keep recording before harvesting — enough to
    /// contain a full follow-through and the hold at the finish.
    private let followThroughWindow: Duration = .milliseconds(1200)

    func start() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        harvester = ClipHarvester(directory: directory)

        let pose = PoseMonitor(
            onSample: { [weak self] sample in
                Task { @MainActor in self?.ingest(pose: sample) }
            },
            onFrame: { [weak self] buffer, time in
                Task { @MainActor in self?.ingest(frame: buffer, at: time) }
            }
        )
        let audio = AudioImpactMonitor { [weak self] onset in
            Task { @MainActor in self?.ingest(impact: onset) }
        }
        poseMonitor = pose
        audioMonitor = audio

        do {
            try await capture.configure(videoDelegate: pose, audioDelegate: audio)
            capture.start()
        } catch {
            // TODO: surface a real setup failure on the coach display rather than
            // leaving the golfer looking at a blank screen.
        }
    }

    // MARK: Ingest

    private func ingest(frame: CMSampleBuffer, at time: Timestamp) {
        if lastFormat == nil {
            lastFormat = CMSampleBufferGetFormatDescription(frame)
        }
        frames.append(frame, at: time)
    }

    private func ingest(pose sample: PoseSample) {
        track.append(sample)
        // Keep only as much history as the segmenter could ever need.
        track.trim(toTrailing: 8.0)

        if machine.state == .idle {
            apply(machine.handle(.personAppeared))
        }

        guard let hand = sample.handPosition(),
              let torso = track.referenceTorsoLength() else { return }
        switch addressWatcher.update(hand: hand, torsoLength: torso, at: sample.time) {
        case .held: apply(machine.handle(.addressHeld))
        case .broken: apply(machine.handle(.addressBroken))
        case nil: break
        }
    }

    private func ingest(impact onset: ImpactOnset) {
        // The state machine drops this on the floor unless we are armed. That is
        // the whole defence against the bay next door.
        apply(machine.handle(.impactHeard(onset.time)))

        guard case .capturing = machine.state else { return }
        captureDeadline?.cancel()
        captureDeadline = Task { [followThroughWindow] in
            try? await Task.sleep(for: followThroughWindow)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.apply(self.machine.handle(.captureWindowElapsed)) }
        }
    }

    // MARK: Effects

    private func apply(_ effects: [SwingEffect]) {
        for effect in effects {
            switch effect {
            case .startPoseTracking:
                poseMonitor?.setEnabled(true)
            case .stopPoseTracking:
                poseMonitor?.setEnabled(false)
            case .showFramingGuides:
                surface = .live
            case .showWaitingForAddress:
                surface = .live
            case .returnToLive:
                surface = .live
                addressWatcher.reset()
            case .startReplay:
                if let clip = swings.last {
                    surface = .replay(clip)
                    scheduleReplayEnd(for: clip)
                }
            case .stopReplay:
                replayTask?.cancel()
                surface = .live
            case .harvestClip(let impact):
                Task { await harvest(impact: impact) }
            }
        }
    }

    private func harvest(impact: Timestamp) async {
        guard let harvester, let format = lastFormat else {
            apply(machine.handle(.segmentationFailed))
            return
        }

        do {
            let segmentation = try segmenter.segment(track: track, impact: impact)
            let range = segmentation.clipRange()
            guard frames.covers(range) else {
                // The swing began before the oldest frame we still hold, so the
                // clip would be truncated. Better to drop it than to show the
                // golfer half an address position.
                apply(machine.handle(.segmentationFailed))
                return
            }

            let url = try await harvester.harvest(
                frames: frames.entries(in: range),
                range: range,
                formatHint: format
            )
            let clip = SwingClip(
                id: UUID(),
                url: url,
                recordedAt: .now,
                segmentation: segmentation,
                metrics: SwingMetricsCalculator.metrics(track: track, segmentation: segmentation),
                frameRate: capture.activeFrameRate,
                angle: cameraAngle
            )
            swings.append(clip)
            selectedSwing = clip.id
            apply(machine.handle(.segmentationSucceeded))
        } catch {
            apply(machine.handle(.segmentationFailed))
        }
    }

    /// Hands the screen back to live framing once the golfer has seen the swing
    /// a few times, so the loop closes without anyone touching the phone.
    private func scheduleReplayEnd(for clip: SwingClip) {
        replayTask?.cancel()
        let seconds = clip.segmentation.totalDuration / replayRate * replayLoops
        replayTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.apply(self.machine.handle(.replayFinished)) }
        }
    }

    func swing(withID id: SwingClip.ID) -> SwingClip? {
        swings.first { $0.id == id }
    }

    func setAngle(_ angle: CameraAngle) {
        cameraAngle = angle
    }
}
