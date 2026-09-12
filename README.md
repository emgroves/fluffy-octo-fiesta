# Swing Mirror

A golf swing evaluation app for iPhone Duo.

Mount the phone open at the range. Hit a shot. Before you've finished your
follow-through, the phone has found the swing, trimmed it, and started looping it
back at you in slow motion on the screen facing you. You never touch it between
shots.

Full plan: [`docs/golf-swing-app-plan.md`](docs/golf-swing-app-plan.md).

## Status

Early scaffold. The core builds and its tests pass in CI; the app target has
never been compiled. See [Verification](#verification).

## How it's laid out

```
Packages/SwingCore/     Pure Swift. Every algorithm that decides what happened
                        in a swing. Foundation and nothing else.
Sources/SwingMirror/    The iOS app. AVFoundation, Vision, SwiftUI, and the
                        iPhone Duo two-display APIs.
docs/                   The plan this is being built against.
```

The split is deliberate and it is the most important decision in the repo.

`SwingCore` holds the impact detector, the address watcher, the swing
segmenter, the state machine and the metrics — expressed over plain numbers
rather than `CMSampleBuffer` and `VNHumanBodyPoseObservation`. That means the
interesting half of the app builds and tests on **any** Swift toolchain,
including Linux CI, with no Mac and no device. `Sources/SwingMirror` is the
adapter layer: it turns Apple's types into the core's types and back, and tries
to hold no judgement of its own.

Practically: if you are changing *what counts as a swing*, you are in
`SwingCore` and you can prove it with `swift test`. If you are changing *how we
get pixels*, you are in the app target and you need hardware.

## Building

The Xcode project is generated, not committed:

```bash
brew install xcodegen
xcodegen generate
open SwingMirror.xcodeproj
```

Requires **Xcode 27.1** (iPhone Duo SDK) and, for anything past a simulator
pose, an **iPhone Duo** — which ships 23 October 2026.

Core tests need no Xcode at all:

```bash
swift test --package-path Packages/SwingCore
```

## Verification

Honest accounting of what is and isn't proven:

| | |
|---|---|
| `SwingCore` logic | **Compiles and passes** on Swift 6.0 — CI runs the suite in a Linux container on every push |
| App target | **Never compiled.** Needs Xcode 27.1, which needs a Mac |
| iPhone Duo APIs | **Unverified against the SDK.** `sceneAccessory`, `CameraCaptureAccessory` and `onAvailabilityChange` are transcribed from Apple's tech talks, not from headers. Reconcile before building |
| Behaviour on a real swing | Not tested, and cannot be until there is footage. The synthetic fixtures model a swing; they do not prove we handle a real one |

First job for anyone with a Mac: `xcodegen generate` and fix whatever the
compiler says. Expect the Duo display APIs in
`Sources/SwingMirror/Stage/StageView.swift` to need correcting first.

## The gating question

`CameraCaptureAccessory` is what puts our own UI on the golfer-facing outer
display. It is available only while the app is full screen on the inner display
with an active capture session, and it is **unavailable when the device is
closed** — so the phone has to be mounted open, not folded.

Apple's worked example for an accessory scene is a teleprompter: static text.
Whether *looping video* renders there acceptably is unproven, and it decides
whether this product works as designed. That is spike S1, and it should be
answered before anything else is built on top of it.

Fallback if video is restricted: decode frames and draw into an
`AVSampleBufferDisplayLayer` or a Metal view.

## Why the core measures stillness, not speed

The first version of the segmenter thresholded frame-to-frame hand speed. That
was wrong, and the arithmetic says why: differentiating a pose track multiplies
position jitter by the inference rate. At 60 Hz, four pixels of Vision jitter on
a 1080p frame becomes ~0.9 torso-lengths/sec of phantom speed — more than twice
any threshold that could separate a still golfer from a moving one.

Measured on the synthetic fixture, the speed-based version put the top of the
backswing at 0.98 s (truth: 1.75 s) with just **two** pixels of jitter, and
failed outright at eight. It mistook a noise dip during the address for the top.

So stillness is measured as the spread of the hands from their centroid over a
window. A still golfer reads ~0.03 torso lengths, a golfer mid-backswing ~0.15,
and the top of the backswing is found as the hands' furthest point from address
— a reversal, not a stillness, so a golfer with no pause at the top still has
one. `testSurvivesRealisticPoseJitter` guards this.

## What this app will not measure

Clubhead speed, ball speed, smash factor, launch angle, spin, carry distance,
face angle at impact.

These need radar or calibrated stereo high-speed capture. At 240 fps a clubhead
travels roughly 19 cm between frames — it is a blurred streak, not a measurable
object. Any phone app claiming these numbers is estimating, and a golfer with a
launch monitor will catch it immediately.

Saying so plainly is better positioning than a number that's wrong by 8%.

## Privacy

Video of people, sometimes children. Everything stays on device. No cloud upload
without explicit opt-in.
