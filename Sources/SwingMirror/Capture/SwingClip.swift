import Foundation
import SwingCore

/// A swing that made it to disk.
struct SwingClip: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let recordedAt: Date
    let segmentation: SwingSegmentation
    let metrics: SwingMetrics
    let frameRate: Double
    let angle: CameraAngle

    /// Roughly 25–30 MB for four seconds of 1080p240 HEVC. Eighty swings is a
    /// 2.4 GB session, which is why retention is a Phase 2 blocker and not a
    /// nicety — see docs/golf-swing-app-plan.md §9.
    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
