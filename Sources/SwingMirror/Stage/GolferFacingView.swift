import SwiftUI
import SwingCore

/// What the golfer sees, eight to ten feet away, in direct sun.
///
/// Design rules, all of which come from that sentence: no touch targets, one
/// idea on screen at a time, and type large enough to read at distance. The
/// outer display peaks at 3000 nits, so contrast is affordable — detail is not.
struct GolferFacingView: View {
    @Bindable var model: SwingSessionModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.surface {
            case .live:
                LiveFramingSurface(model: model)
            case .replay(let clip):
                ReplaySurface(clip: clip, headline: model.headline)
            case .waiting:
                WaitingSurface()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LiveFramingSurface: View {
    @Bindable var model: SwingSessionModel

    var body: some View {
        ZStack {
            CameraPreview(session: model.captureSession)
                .ignoresSafeArea()

            FramingGuides(angle: model.cameraAngle)

            VStack {
                Spacer()
                Text(model.framingHint)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .shadow(radius: 8)
            }
        }
    }
}

private struct ReplaySurface: View {
    let clip: SwingClip
    let headline: String?

    var body: some View {
        ZStack {
            // Spike S1: this is the call that has to be proven. Apple's worked
            // example for an accessory scene is a teleprompter — static text.
            // Whether looping video plays here, and at what latency, decides the
            // whole product. Fallback if it does not: decode frames ourselves and
            // draw into a Metal layer.
            ReplayPlayerView(clip: clip)
                .ignoresSafeArea()

            if let headline {
                VStack {
                    Spacer()
                    Text(headline)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.vertical, 14)
                        .padding(.horizontal, 28)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 36)
                }
            }
        }
    }
}

private struct WaitingSurface: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "figure.golf")
                .font(.system(size: 96, weight: .light))
            Text("Ready")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
    }
}
