import AVFoundation
import Vision
import SwingCore

/// Turns video frames into `SwingCore.PoseSample`s.
///
/// Inference runs at a fraction of the capture rate — around 30 Hz against 240
/// fps of video. The extra frames buy us temporal resolution in the *replay*,
/// not in the pose track, and running Vision on all of them would cook the
/// phone for no benefit.
final class PoseMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let inferenceInterval: Double
    private let onSample: @Sendable (PoseSample) -> Void
    private let onFrame: @Sendable (CMSampleBuffer, Timestamp) -> Void

    private var lastInference: Timestamp = -.greatestFiniteMagnitude
    private var enabled = true

    init(
        inferenceRate: Double = 30,
        onSample: @escaping @Sendable (PoseSample) -> Void,
        onFrame: @escaping @Sendable (CMSampleBuffer, Timestamp) -> Void
    ) {
        self.inferenceInterval = 1.0 / inferenceRate
        self.onSample = onSample
        self.onFrame = onFrame
    }

    /// Pose tracking pauses during replay. That is roughly a third of a range
    /// session, and the cheapest thermal saving available to us.
    func setEnabled(_ value: Bool) { enabled = value }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Every frame goes to the ring buffer regardless — that is the footage we
        // will reach back into once a swing is confirmed.
        onFrame(sampleBuffer, time)

        guard enabled, time - lastInference >= inferenceInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastInference = time

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return }
            if let sample = Self.poseSample(from: observation, at: time) {
                onSample(sample)
            }
        } catch {
            // A dropped inference is not an error worth surfacing; the segmenter
            // is built to tolerate gaps in the track.
        }
    }

    static func poseSample(
        from observation: VNHumanBodyPoseObservation,
        at time: Timestamp
    ) -> PoseSample? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        var readings: [Joint: JointReading] = [:]
        for (joint, visionName) in visionJointNames {
            guard let point = points[visionName], point.confidence > 0 else { continue }
            // Vision's origin is bottom-left; ours is top-left, matching how the
            // frame is drawn. Flip y once, here, so no metric has to think about it.
            readings[joint] = JointReading(
                position: Point(x: point.location.x, y: 1 - point.location.y),
                confidence: Double(point.confidence)
            )
        }
        guard !readings.isEmpty else { return nil }
        return PoseSample(time: time, readings: readings)
    }

    private static let visionJointNames: [Joint: VNHumanBodyPoseObservation.JointName] = [
        .nose: .nose,
        .leftShoulder: .leftShoulder,
        .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow,
        .rightElbow: .rightElbow,
        .leftWrist: .leftWrist,
        .rightWrist: .rightWrist,
        .leftHip: .leftHip,
        .rightHip: .rightHip,
        .leftKnee: .leftKnee,
        .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle,
        .rightAnkle: .rightAnkle
    ]
}
