import SwiftUI
import SwingCore

/// Every swing of the session, newest first.
///
/// Because capture is hands-free, this list fills itself — which is what makes
/// consistency across a session measurable at all. A coach reads down it.
struct SessionTimeline: View {
    let swings: [SwingClip]
    @Binding var selection: SwingClip.ID?

    var body: some View {
        List(selection: $selection) {
            if swings.isEmpty {
                ContentUnavailableView(
                    "No swings yet",
                    systemImage: "figure.golf",
                    description: Text("Mount the phone open, step into frame, and hit a shot.")
                )
            } else {
                ForEach(swings.reversed()) { swing in
                    SwingRow(swing: swing, index: index(of: swing))
                        .tag(swing.id)
                }
            }
        }
    }

    private func index(of swing: SwingClip) -> Int {
        (swings.firstIndex(where: { $0.id == swing.id }) ?? 0) + 1
    }
}

private struct SwingRow: View {
    let swing: SwingClip
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(tempoText)
                    .font(.headline.monospacedDigit())
                Text(swing.recordedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(swing.frameRate)) fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var tempoText: String {
        guard let ratio = swing.metrics.tempoRatio else { return "Tempo —" }
        return String(format: "Tempo %.1f : 1", ratio)
    }
}

/// The detail panel. Tier A metrics only — see docs/golf-swing-app-plan.md §5.
struct SwingDetail: View {
    let swing: SwingClip?

    var body: some View {
        if let swing {
            List {
                Section("Tempo") {
                    metric("Backswing", seconds: swing.metrics.backswingDuration)
                    metric("Downswing", seconds: swing.metrics.downswingDuration)
                    if let ratio = swing.metrics.tempoRatio {
                        row("Ratio", String(format: "%.2f : 1", ratio))
                    }
                }
                Section("Movement") {
                    if let drift = swing.metrics.headDrift {
                        row("Head drift", String(format: "%.2f torso lengths", drift))
                    }
                    if let change = swing.metrics.spineAngleChange {
                        row("Spine angle change", String(format: "%.1f°", change))
                    }
                }
                Section("Clip") {
                    row("Captured at", "\(Int(swing.frameRate)) fps")
                    row("Angle", swing.angle == .downTheLine ? "Down the line" : "Face on")
                }
            }
        } else {
            ContentUnavailableView("Select a swing", systemImage: "sidebar.right")
        }
    }

    private func metric(_ name: String, seconds: Double) -> some View {
        row(name, String(format: "%.2f s", seconds))
    }

    private func row(_ name: String, _ value: String) -> some View {
        LabeledContent(name) {
            Text(value).monospacedDigit()
        }
    }
}
