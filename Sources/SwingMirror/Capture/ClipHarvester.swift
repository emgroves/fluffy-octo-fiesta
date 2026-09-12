import AVFoundation
import SwingCore

/// Writes a span of buffered frames out as a file.
///
/// Nothing reaches disk until a swing is confirmed: the ring buffer holds the
/// last few seconds continuously, and this reaches backwards into it once the
/// segmenter has said where the swing starts and ends.
actor ClipHarvester {
    enum HarvestError: Error {
        case noFrames
        case bufferDoesNotCoverSwing
        case writerFailed(Error)
    }

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func harvest(
        frames: [TimedRingBuffer<CMSampleBuffer>.Entry],
        range: ClosedRange<Timestamp>,
        formatHint: CMFormatDescription
    ) async throws -> URL {
        guard !frames.isEmpty else { throw HarvestError.noFrames }

        let url = directory.appendingPathComponent("\(UUID().uuidString).mov")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: nil,
                sourceFormatHint: formatHint
            )
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw HarvestError.noFrames }
            writer.add(input)

            writer.startWriting()
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            writer.startSession(atSourceTime: start)

            for entry in frames where range.contains(entry.time) {
                // Yield rather than block: this is an actor, and sleeping on its
                // executor would stall every other caller. The source is already
                // in memory, so back-pressure here is brief.
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                input.append(entry.element)
            }

            input.markAsFinished()
            await writer.finishWriting()

            if let error = writer.error {
                throw HarvestError.writerFailed(error)
            }
            return url
        } catch let error as HarvestError {
            throw error
        } catch {
            throw HarvestError.writerFailed(error)
        }
    }
}
