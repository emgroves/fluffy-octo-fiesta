import SwiftUI
import SwingCore

/// The root view, and the one piece of this app that only exists on iPhone Duo.
///
/// The inner display carries the coach-facing detail; `CameraCaptureAccessory`
/// puts the golfer-facing replay on the outer display. Mounted open, the outer
/// display and the rear cameras face the same way — so the golfer is filmed by
/// the rear cameras and watches themselves on the screen beside the lenses.
///
/// UNVERIFIED AGAINST THE SDK. The scene-accessory API shipped days ago and the
/// shape below is taken from Apple's "Leverage multiple displays and scenes on
/// iPhone Duo" tech talk, not from a compiler. Reconcile against the real
/// headers before building — this is spike S1.
struct StageView: View {
    @Bindable var model: SwingSessionModel

    var body: some View {
        CoachView(model: model)
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $model.golferDisplayEnabled) {
                    GolferFacingView(model: model)
                }
                .onAvailabilityChange { available in
                    model.golferDisplayAvailable = available
                }
            }
    }
}
