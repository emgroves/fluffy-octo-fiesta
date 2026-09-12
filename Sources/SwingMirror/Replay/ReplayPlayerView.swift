import AVKit
import SwiftUI

/// Loops a swing back at the golfer in slow motion.
///
/// Spike S1 lives here. Apple's worked example of an accessory scene is a
/// teleprompter — static text — so whether an `AVPlayer` renders acceptably on
/// the outer display, and with what latency, is unproven. If it does not, the
/// fallback is to decode frames ourselves into an `AVSampleBufferDisplayLayer`
/// or a Metal view, which is more work but entirely within reach.
struct ReplayPlayerView: UIViewControllerRepresentable {
    let clip: SwingClip
    var rate: Float = 0.25

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.clipID != clip.id {
            context.coordinator.load(clip: clip, rate: rate, into: controller)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private(set) var clipID: UUID?
        private var looper: AVPlayerLooper?
        private var queuePlayer: AVQueuePlayer?

        func load(clip: SwingClip, rate: Float, into controller: AVPlayerViewController) {
            let item = AVPlayerItem(url: clip.url)
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = false
            controller.player = player
            player.play()
            player.rate = rate
            queuePlayer = player
            clipID = clip.id
        }
    }
}
