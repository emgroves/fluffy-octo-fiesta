# Swing Mirror — working notes

An iPhone Duo golf swing app. Read `docs/golf-swing-app-plan.md` first; it
carries the reasoning behind almost every decision here.

## The one architectural rule

**Decision logic goes in `Packages/SwingCore`. Platform I/O goes in
`Sources/SwingMirror`.**

`SwingCore` imports Foundation and nothing else — no AVFoundation, no Vision, no
SwiftUI, no CoreMedia. That is what lets it build and test on Linux CI without a
Mac or a device, and it is the only reason any of this is verifiable before
hardware ships.

When you add behaviour, ask which side it belongs on:

- "Was that a swing?", "when did the backswing end?", "is this golfer at
  address?", "what is their tempo?" → `SwingCore`, with tests.
- "How do I get a pixel buffer?", "which display is this view on?", "how do I
  write a .mov?" → app target.

If you find yourself wanting `import AVFoundation` inside `SwingCore`, the type
you need is probably a plain `Double` and a timestamp.

## Conventions

- Swift 6 language mode, strict concurrency complete.
- The app target is `@MainActor` by default; `CaptureController` is confined to
  its own serial queue and marked `@unchecked Sendable` with that confinement
  stated in a comment.
- Timestamps everywhere are `SwingCore.Timestamp` (seconds, `Double`) on the
  shared capture clock. Audio and video share it — that is what lets a strike
  heard on the mic name a video frame.
- Pose coordinates are normalised with origin **top-left**. Vision's origin is
  bottom-left; the flip happens once, in `PoseMonitor.poseSample(from:at:)`, so
  no metric has to think about it.
- Distances are expressed in **torso lengths**, never pixels, so a metric means
  the same thing at six feet and at twelve.
- **Never threshold a derivative of the pose track.** Differentiating multiplies
  position jitter by the inference rate; four pixels of Vision jitter becomes
  ~0.9 torso-lengths/sec of phantom speed. Stillness is measured as spread from
  a windowed centroid (`PoseTrack.stillnessSeries`, `AddressWatcher`), and the
  top of the backswing as the hands' furthest point from address. See README,
  "Why the core measures stillness, not speed".

## Testing

```bash
swift test --package-path Packages/SwingCore
```

There is no unit test for a golf swing, so `Tests/SwingCoreTests/Fixtures.swift`
synthesises one: a scripted hand path with known key moments, and a deterministic
noise bed with bursts in it. Nothing in the tests uses the system RNG — a
detector test that flakes is worse than no test.

The plan (§9) calls for a fixture corpus of real recorded swings with
hand-labelled ground truth, run headlessly in CI, asserting impact-frame error
≤ 2 frames, zero missed swings, and under one false positive per fifty clips.
That replaces the synthetic fixtures once there is footage to label.

## Unverified surface

`SwingCore` compiles and its tests pass in CI. The app target does not build
anywhere yet, and these have never been compiled against the real SDK — they are
transcribed from Apple's iPhone Duo tech talks:

- `.sceneAccessory { }`, `CameraCaptureAccessory(isEnabled:)`,
  `.onAvailabilityChange { }` in `Stage/StageView.swift`
- `ArrangementView` in `Stage/CoachView.swift`

Fix these against headers before trusting anything downstream of them.

## Don't

- Don't add clubhead speed, ball speed, launch angle or face angle. See
  README, "What this app will not measure". This is a positioning decision, not
  a backlog item.
- Don't run Vision on every captured frame. Inference is decimated to ~30 Hz
  against 240 fps of video, and it pauses entirely during replay — that is the
  cheapest thermal saving available to us.
- Don't write to disk before a swing is confirmed. Frames live in the ring
  buffer; only a segmented swing becomes a file.
