import AVFoundation
import SwingCore

enum CameraAngle: String, Sendable, CaseIterable {
    case downTheLine
    case faceOn

    var guidanceText: String {
        switch self {
        case .downTheLine: "Stand on the target line, ball between you and the phone"
        case .faceOn: "Turn side-on to the phone, chest facing the lens"
        }
    }
}

/// Owns the `AVCaptureSession`.
///
/// Confined to `queue`: `AVCaptureSession` is not `Sendable`, and every touch of
/// it happens on that one serial queue. The `@unchecked` is that confinement,
/// stated rather than assumed.
final class CaptureController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.swingmirror.capture")
    let session = AVCaptureSession()

    private var videoDevice: AVCaptureDevice?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    /// Frame rate actually achieved, which is not always the one we asked for —
    /// thermal pressure walks this down. See `degrade(to:)`.
    private(set) var activeFrameRate: Double = 0

    enum CaptureError: Error {
        case noRearCamera
        case noHighSpeedFormat
        case cannotAddInput
        case cannotAddOutput
    }

    func configure(
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        audioDelegate: AVCaptureAudioDataOutputSampleBufferDelegate
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.configureOnQueue(
                        videoDelegate: videoDelegate,
                        audioDelegate: audioDelegate
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue(
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        audioDelegate: AVCaptureAudioDataOutputSampleBufferDelegate
    ) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .inputPriority

        // The 48MP Fusion main camera. The Duo has no dedicated telephoto — "2x"
        // is a crop of this sensor — so at eight to ten feet we are living with
        // 24mm and the perspective that comes with it.
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { throw CaptureError.noRearCamera }
        videoDevice = device

        guard let format = Self.highestFrameRateFormat(for: device, preferredHeight: 1080) else {
            throw CaptureError.noHighSpeedFormat
        }

        try device.lockForConfiguration()
        device.activeFormat = format
        let rate = format.videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max() ?? 60
        let duration = CMTime(value: 1, timescale: CMTimeScale(rate.rounded()))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
        activeFrameRate = rate

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else { throw CaptureError.cannotAddInput }
        session.addInput(videoInput)

        if let mic = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: queue)
        guard session.canAddOutput(videoOutput) else { throw CaptureError.cannotAddOutput }
        session.addOutput(videoOutput)

        audioOutput.setSampleBufferDelegate(audioDelegate, queue: queue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
    }

    func start() {
        queue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Steps the capture rate down under thermal pressure.
    ///
    /// 240 fps plus encode plus inference, outdoors, for forty-five minutes will
    /// throttle. Losing temporal resolution gracefully beats the system deciding
    /// for us mid-swing.
    func degrade(to frameRate: Double) {
        queue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
                self.activeFrameRate = frameRate
            } catch {
                // Nothing useful to do here; the next thermal tick will retry.
            }
        }
    }

    /// The fastest format at or near the preferred height.
    ///
    /// At 240 fps a driver's downswing is about sixty frames — plenty for body
    /// motion, and still not enough to freeze a clubhead, which travels roughly
    /// 19 cm between frames near impact.
    static func highestFrameRateFormat(
        for device: AVCaptureDevice,
        preferredHeight: Int
    ) -> AVCaptureDevice.Format? {
        var best: AVCaptureDevice.Format?
        var bestRate = 0.0

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard Int(dimensions.height) == preferredHeight else { continue }
            guard let rate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() else {
                continue
            }
            if rate > bestRate {
                bestRate = rate
                best = format
            }
        }
        return best
    }
}
