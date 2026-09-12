import AVFoundation
import SwingCore

/// Bridges captured audio into the pure-Swift onset detector.
///
/// Everything interesting happens in `SwingCore.ImpactOnsetDetector`; this file
/// only knows how to turn a `CMSampleBuffer` into an array of floats and a
/// timestamp on the shared capture clock. That split is what lets the detection
/// logic be tested without a device.
final class AudioImpactMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let detector: ImpactOnsetDetector
    private let onImpact: @Sendable (ImpactOnset) -> Void

    init(
        configuration: ImpactDetectorConfiguration = ImpactDetectorConfiguration(),
        onImpact: @escaping @Sendable (ImpactOnset) -> Void
    ) {
        self.detector = ImpactOnsetDetector(configuration: configuration)
        self.onImpact = onImpact
    }

    func reset() { detector.reset() }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let samples = Self.monoSamples(from: sampleBuffer) else { return }
        let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        for onset in detector.process(samples, startTime: start) {
            onImpact(onset)
        }
    }

    /// Flattens whatever the mic gave us into mono float samples.
    static func monoSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let data = audioBufferList.mBuffers.mData else { return nil }

        let count = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        let pointer = data.bindMemory(to: Float.self, capacity: count)
        let interleaved = Array(UnsafeBufferPointer(start: pointer, count: count))

        let channels = Int(asbd.mChannelsPerFrame)
        guard channels > 1, asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else {
            return interleaved
        }
        return stride(from: 0, to: interleaved.count, by: channels).map { interleaved[$0] }
    }
}
