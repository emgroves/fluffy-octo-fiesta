import AVFoundation
import SwiftUI

/// Live preview, used while the golfer is framing themselves.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// Framing guides, drawn large enough to act on from ten feet away.
struct FramingGuides: View {
    let angle: CameraAngle

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Rectangle()
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, dash: [12, 10]))
                    .frame(width: size.width * 0.62, height: size.height * 0.86)

                if angle == .downTheLine {
                    // The target line the golfer should be standing on.
                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.2))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.95))
                    }
                    .stroke(.yellow.opacity(0.65), lineWidth: 2)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}
