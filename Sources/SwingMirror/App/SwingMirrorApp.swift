import SwiftUI

@main
struct SwingMirrorApp: App {
    @State private var session = SwingSessionModel()

    var body: some Scene {
        WindowGroup {
            StageView(model: session)
                .task { await session.start() }
                // A mounted phone must never sleep between shots.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
