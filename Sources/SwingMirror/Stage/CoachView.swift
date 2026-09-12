import SwiftUI
import SwingCore

/// The inner display — which, with the phone mounted open, faces away from the
/// golfer and toward whoever is standing behind it.
///
/// That is the most distinctive thing this hardware gives us: the student
/// watches their swing while a coach simultaneously reads the analysis. It is
/// also where all the complexity belongs, because the person reading it is
/// standing still.
struct CoachView: View {
    @Bindable var model: SwingSessionModel

    var body: some View {
        NavigationStack {
            ArrangementView {
                SessionTimeline(swings: model.swings, selection: $model.selectedSwing)
            } secondary: {
                SwingDetail(swing: model.selectedSwing.flatMap(model.swing(withID:)))
            }
            .navigationTitle("Session")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("Golfer display", isOn: $model.golferDisplayEnabled)
                        .disabled(!model.golferDisplayAvailable)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.golferDisplayAvailable {
                    // Accessory availability is system-controlled and can be
                    // withdrawn mid-session. Never show the golfer a dead screen —
                    // say what happened and what to do about it.
                    StatusBanner(
                        message: "The golfer-facing display is unavailable. Open the phone fully and keep Swing Mirror full screen.",
                        tone: .warning
                    )
                }
            }
        }
    }
}

private struct StatusBanner: View {
    enum Tone { case warning, neutral }

    let message: String
    let tone: Tone

    var body: some View {
        Text(message)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tone == .warning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
    }
}
