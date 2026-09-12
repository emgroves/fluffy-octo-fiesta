# Swing Mirror — iPhone Duo Golf Swing Evaluation App

**Planning document — v1, 12 September 2026**

---

## 1. The idea, stated precisely

Mount the iPhone Duo behind or beside you at the range. Hit a shot. Before you've
finished your follow-through, the phone has already found the swing, trimmed it,
and started looping it back at you in slow motion on the screen facing you. You
never touch the phone between shots.

That closed feedback loop — swing, see it, adjust, swing again — is the entire
product. Everything else is decoration.

---

## 2. Does the hardware actually allow this? Yes, with one hard constraint

This is the question that decides whether the project exists, so it goes first.

### What Apple shipped

The Duo's headline camera trick is **Duo Preview**: point the rear cameras at
someone and they see a live preview on the outer display. That's a system Camera
app feature. The question is whether *we* get the same capability.

We do, via **`CameraCaptureAccessory`**, part of the new scene-accessories API in
the iOS 27.1 SDK:

```swift
struct CaptureRootView: View {
    @State private var model = SwingSessionModel()

    var body: some View {
        CoachView(model: model)                    // inner display
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $model.outerDisplayEnabled) {
                    GolferFacingView(model: model) // outer display
                }
                .onAvailabilityChange { model.accessoryAvailable = $0 }
            }
    }
}
```

Apple's own worked example is a **teleprompter** on the outer display while the
camera runs on the inner one. That matters enormously: a teleprompter is
arbitrary scrolling SwiftUI content, not a constrained system preview. It means
the outer display accepts **our** views — which is exactly what we need, because
we want to show a *replay*, not a live preview.

### The hard constraint

`CameraCaptureAccessory` is only available when **all** of these hold:

1. The app is **full screen on the inner display**
2. A **capture session is active**
3. The device is in a supported configuration — **accessories are unavailable
   when the device is closed**

Number 3 kills the obvious mental image of a folded phone propped up like a
compact mirror. **The Duo must be mounted open.**

### What that means physically

On a book-style fold, when the device is open, the outer display and the rear
cameras both sit on the back — they face the *same* direction, away from the
inner display. So the mounted geometry is:

```
                          ┌──────────────────────────┐
   GOLFER  ◄───────────── │  outer display │ cameras │  ◄── device open, flat
   (8-10 ft)              ├──────────────────────────┤
                          │     inner display        │ ──► faces away
                          └──────────────────────────┘
```

The golfer sees the outer display and is filmed by the rear cameras. This is
precisely the Duo Preview arrangement, which is reassuring — we're using the
hardware the way it was designed to be used.

**And it hands us a free second screen.** The inner display faces away from the
golfer, which is exactly where a coach or playing partner stands. That is a
genuinely novel product surface: *the student sees their swing, the coach
simultaneously sees the analysis.* No other phone can do this. If this app has a
reason to exist on the Duo specifically, that's it — not the folding.

### Also relevant

- `AVCaptureDeviceDirectionCoordinator` (in AVKit) replaces the old fixed
  `.front`/`.back` position property. It reports which cameras face forward or
  backward *relative to the view's display*, and fires a change handler when the
  device opens, closes or flips. We need one per display surface.
- `onHingeChange` / `UIHingeInteraction` expose discrete hinge states and a
  continuous angle — useful to confirm the device is open and propped, and to
  detect if someone knocks the mount.
- `reservedRegions(kind: .division)` reports where the fold falls; `.occlusion`
  reports the camera cutouts. Inner-display layout must route around both.
- Apple's guidance is that opening or folding should never be *required* to reach
  a feature. We bend this — the core loop genuinely requires the open pose — so
  we must degrade gracefully rather than show a dead end. See §8.

### Hardware facts that shape the design

| | |
|---|---|
| Inner display | 7.6" (7.58" as a rectangle), Super Retina XDR, ProMotion |
| Outer display | 5.4", same panel tech, **3000 nits peak outdoor** |
| Rear cameras | 48MP Fusion main (24mm, f/1.6) + 48MP ultrawide (13mm, f/2.2). **No telephoto** — "2x" is a 52mm crop of the main sensor |
| Slow motion | **1080p @ 240fps**, or 4K @ 120fps |
| Chip | A20 Pro, vapor chamber, dual-battery architecture |
| Weight / thickness | 254g, 5.2mm open, 11.3mm folded |
| Charging | MagSafe + Qi2, 25W |
| Price / availability | $1,999 · pre-order 16 Oct · **ships 23 Oct 2026** |

3000 nits on the outer display is the unsung hero here — replay will actually be
readable in direct sun, which is where this app lives.

**The device does not ship for six weeks.** Everything before 23 October is
simulator work (Xcode 27.1, Device Hub poses) plus pipeline work that can be
built and tested on any current iPhone. Plan accordingly; see §7.

---

## 3. Repository reality check

This repo is currently an Expo / React Native `create-expo-app` starter
(a tic-tac-toe scaffold). **It should be replaced, not extended.**

Every API this product depends on — `sceneAccessory`, `CameraCaptureAccessory`,
`AVCaptureDeviceDirectionCoordinator`, high-frame-rate `AVCaptureSession`
configuration, Vision body-pose requests, Metal overlay rendering — is brand-new
native iOS, shipped days ago, with no React Native bridge and no realistic
prospect of one soon. Bridging them yourself means writing all the hard parts in
Swift anyway and then paying a marshalling tax on a 240fps video pipeline.

**Recommendation: a native SwiftUI app, Swift 6, deployment target iOS 27.1.**

---

## 4. How the capture loop works

This is the engineering heart of the app. Three problems: catch the swing without
being told, find its boundaries, and do it fast enough that replay feels instant.

### 4.1 Ring buffer, not record-on-command

You cannot ask a golfer to press record. By the time any trigger fires, the swing
is already over. So the capture session runs continuously and writes compressed
sample buffers into an **in-memory circular buffer** holding the last ~8 seconds.
At 1080p240 HEVC (~50 Mbps) that's roughly 50 MB resident — comfortable.

When a swing is detected, we retroactively extract the relevant span and hand it
to `AVAssetWriter`. Nothing is written to disk until we know we have a swing.

### 4.2 The trigger: listen for the strike

**The microphone is the best swing detector available, and most apps ignore it.**

A struck golf ball produces a sharp, loud, broadband transient — a far cleaner
signal than anything in the video. A lightweight onset detector (high-pass →
energy envelope → adaptive threshold) fires within milliseconds and, because
audio and video share a capture clock, hands us the **impact timestamp accurate
to well within one frame**. That single number anchors the entire segmentation.

It also solves a problem vision-only detection handles badly: **practice swings
produce no impact transient**, so they're filtered out for free.

The catch is a busy range — you will hear your neighbour's shot. So the audio
trigger is *gated* by vision: `VNDetectHumanBodyPoseRequest` running on a
decimated stream (~30fps, not 240) must confirm that a person is in frame, was at
address, and has just moved through a swing. Audio says *when*, vision says
*whether*. Neither alone is sufficient.

### 4.3 Segmentation

From the impact timestamp, walk the pose track outward:

- **backward** to find the top of the backswing (wrist velocity sign change),
  then the takeaway (velocity onset), then address (stillness)
- **forward** to find the finish (stillness returns)

Clip = address − 0.3s to finish + 0.5s. Typically 2.5–4 seconds.

### 4.4 State machine

```
IDLE → FRAMING → ARMED → CAPTURING → SEGMENTING → REPLAY ─┐
         ▲                                                 │
         └─────────────────────────────────────────────────┘
```

`FRAMING` shows live preview with guides on the outer display so you can position
yourself. `ARMED` waits, running vision but no heavy work. `REPLAY` loops the
swing. Vision inference is **suspended during REPLAY** — a meaningful thermal
saving, since that's a third of the wall-clock time in a range session.

### 4.5 Frame rate honesty

At 240fps a driver's downswing gives ~60 frames — plenty to see body motion, load
and sequencing. But the clubhead travels roughly **19cm between frames** near
impact. It will be a blurred streak. That is a physical limit, not a software
problem, and it constrains what we can claim to measure (§5).

Two more capture realities worth designing around:

- **Exposure.** 240fps caps shutter at 4.17ms regardless. Bright sun is fine;
  dusk and indoor bays will be noisy. Ship a setup-time lighting check.
- **Rolling shutter.** A fast shaft skews on a CMOS sensor. This degrades any
  shaft-angle measurement taken near impact — another reason to be conservative
  about club metrics.
- **Focal length.** With no true telephoto, down-the-line framing at 8–10 ft uses
  the 24mm main camera, which is wider than ideal and will add perspective
  distortion at the frame edges. Whether the 52mm sensor crop is available *in
  the 240fps format* is an open question and a Phase 0 spike.

---

## 5. What we can honestly measure

The fastest way to lose a golfer's trust is to show them a number that's wrong.
Three tiers, and we should be public about which is which.

### Tier A — reliable from one 2D camera. Build these.

- **Tempo ratio** (backswing frames : downswing frames — the classic ~3:1) and
  absolute swing duration
- **Key frame extraction** at the standard positions: address, shaft parallel,
  top, shaft parallel down, impact, finish
- **Head movement** — sway and lift, normalised against a body-length scale
- **Spine angle** at address and its change through the swing (down-the-line)
- **Early extension** — pelvis drifting toward the ball line (down-the-line)
- **Hip and shoulder rotation proxies**, lead arm straightness at the top
- **Setup consistency** — how repeatable your address position is
- **Swing-to-swing variance across a session**

That last one deserves emphasis. Because this app captures *every* swing
automatically, it can say something no launch monitor and no coach with a phone
can: *"your tempo was 3.1:1 for the first twenty balls and 2.4:1 for the last
ten — you got quick when you got tired."* Consistency data is the natural
product of hands-free capture, and it's the most defensible feature here.

### Tier B — real work, later phases

- **Swing plane visualisation.** Needs shaft tracking. A hands-path proxy gets
  most of the value for a fraction of the effort — do that first.
- **Club/shaft tracking.** A thin, fast, motion-blurred object against arbitrary
  backgrounds. This needs a custom Core ML model and a labelled dataset in the
  thousands of frames. Genuinely hard. Phase 4 at the earliest.
- **3D pose** via `VNHumanBodyPose3DRequest`. Worth evaluating, but it's tuned
  for everyday human motion, not a body rotating at speed. Expect it to struggle.

### Tier C — not possible. Do not build, do not market.

Clubhead speed, ball speed, smash factor, launch angle, spin rate, carry
distance, face angle at impact. These require radar or calibrated stereo
high-speed capture. Any phone app claiming them from a single camera is
estimating, and golfers with launch monitors will catch it immediately.

Saying "we don't measure ball speed, and here's why" is better positioning than a
number that's wrong by 8%.

---

## 6. The two screens

### Outer display — the golfer, 8–10 feet away, in sunlight

Design constraints: no touch input, glanceable in under a second, readable at
distance and at 3000 nits in full sun. Everything large and high-contrast.

Sequence after a swing lands:

1. Replay auto-plays immediately at 0.25×, looping
2. Skeleton overlay and key-frame markers
3. **One** headline number — not a dashboard. Tempo, or whatever the user pinned
4. After ~3 loops, return to live preview with framing guides
5. Ready for the next ball

Comparison mode ghosts your baseline swing over the current one. Voice control
(`SFSpeechRecognizer`, on-device) for "replay", "slower", "compare", "delete
that one" — useful, but wind and range noise make it unreliable, so it stays
optional and never load-bearing.

### Inner display — the coach, or the detail view

Session timeline of every swing, full metric breakdown, trends across the
session, settings, retention management. This is where complexity is allowed to
live, because the person looking at it is standing still and holding nothing.

---

## 7. Phasing and schedule

### Phase 0 — Feasibility spikes · now → hardware · ~3 weeks

The device ships 23 October. Use the gap to de-risk, on simulator and on current
iPhones.

| # | Spike | Why it's dangerous |
|---|---|---|
| **S1** | Can `CameraCaptureAccessory` host looping **video playback**? At what latency and frame rate? | **The gating spike.** Apple's example is a teleprompter — static text. If video in an accessory scene is restricted, throttled, or laggy, the core concept needs rework. Fallback: render decoded frames into a Metal layer rather than using `AVPlayer`. |
| **S2** | Is **1080p240** still offered while an accessory scene is active? Is the 52mm crop available in that format? | An accessory might force a lower-power capture path. Would cost us half our temporal resolution. |
| **S3** | Audio impact detection against recorded range audio, including neighbouring bays | Determines whether the hands-free trigger works in the real world or only in a quiet backyard |
| **S4** | Vision pose quality on decimated 240fps golf footage | Pose estimators are trained on walking, not on a body rotating at 300°/s |
| **S5** | Sustained thermals: 240fps capture + encode + inference on an iPhone 18 Pro as an A20 proxy | Tells us whether a 45-minute range session is realistic before we build for it |

**Exit criteria: an explicit go / rework / no-go on the core loop.** S1 and S2 are
the ones that can change the product.

### Phase 1 — "The Mirror" · 4–5 weeks after hardware · target TestFlight early December

Mount, frame, auto-detect, auto-trim, auto-replay in slow motion on the outer
display. **No analysis whatsoever.** No metrics, no skeleton, no numbers.

This is the minimum thing worth shipping, and it is already a product. A golfer
who can see their last swing without walking to the phone has something they
could not previously buy. Resist the urge to add metrics here — if the loop isn't
compelling without them, metrics won't save it, and you'll have learned that
cheaply.

### Phase 2 — Overlays and tempo · 3–4 weeks

Pose skeleton, key frames, tempo ratio, head movement. Session list and detail on
the inner display. Retention policy and storage management ship here — they must
not slip past this point (§9).

### Phase 3 — Comparison and consistency · 3–4 weeks

Baseline swing, ghosted overlay comparison, session consistency reporting,
clip export and share. This is where the app becomes *sticky* rather than novel.

### Phase 4 — and beyond

Club/shaft tracking, drill library, structured coach mode, optional cloud sync,
subscription.

### Realistic dates

- **Phase 1 TestFlight: early December 2026**
- **App Store release covering Phases 1–3: February–March 2027**

### Team

- 1 senior iOS engineer with genuine AVFoundation depth — not a generalist who
  has used `UIImagePickerController`
- 1 computer vision / ML engineer
- Part-time designer (the outer-display work is unusual and matters a lot)
- **A teaching professional on retainer.** Non-negotiable. Every metric needs
  someone who teaches golf for a living to confirm it means what you think it
  means.

One very strong generalist could do it alone at roughly 1.6× the timeline.

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Video playback restricted or laggy in the accessory scene** | **Critical** | Spike S1 before anything else. Fallback to Metal-rendered frames. |
| **Accessory availability revoked mid-session** — it is system-controlled and can toggle at any time | **High** | `onAvailabilityChange` must be handled from day one. Fall back to replay on the inner display plus an audio cue telling the user to check the mount. Never a dead screen. |
| **Thermal throttling** over a 45-minute session in the sun | **High** | Watch `ProcessInfo.thermalState`; degrade 240 → 120 → 60fps. Suspend inference during replay. Target <6W sustained. Expect 90–120 min continuous; recommend a battery pack. |
| **Mounting a $1,999 open foldable at a driving range** | **High** | No mount exists for this form factor. MagSafe/Qi2 magnets are present, but which half carries them needs checking on real hardware. Early users will improvise; ship a setup guide with tested configurations and consider a mount partnership. |
| **False triggers from neighbouring bays** | Medium | Vision gating (§4.2); per-session calibration of the audio threshold; easy "delete that one" |
| **Tiny addressable market** — Duo owners who also golf | Medium | Treat as a lighthouse app. Plan a degraded non-Duo mode (capture on any iPhone, replay when you walk over, or an Apple Watch companion as remote and trigger). |
| **Low light** at dusk or in indoor bays | Medium | Lighting check at setup; automatic drop to 120fps for a longer shutter |
| **Metrics that a teaching pro would dispute** | Medium | The pro on retainer. Publish Tier C honestly. |
| **Hardware unavailable until 23 Oct** | Low | Phase 0 is designed around this |

---

## 9. Things that are easy to forget

**Storage.** A 4-second clip at 1080p240 HEVC is roughly 25–30 MB. Eighty swings
is ~2.4 GB — *per session*. Without a retention policy this app quietly eats a
user's phone in a fortnight. Ship one in Phase 2 at the latest: keep flagged
swings at full rate, transcode the rest to 60fps after the session, auto-delete
after N days with clear warning.

**Privacy.** This app records video of people, including junior golfers.
Everything stays on-device by default, no cloud upload without explicit opt-in.
This is both correct and good marketing — say it on the App Store page.

**Testing something you can't unit test.** You cannot write a unit test for a
golf swing, so build a **fixture corpus**: several dozen recorded swings with
hand-labelled ground truth for address, top, impact and finish. Run the trigger
and segmentation pipeline headlessly over the corpus in CI, and assert:
impact-frame error ≤ 2 frames, zero missed swings, fewer than one false positive
per fifty clips. Snapshot-test the overlay renderer. Use Device Hub poses to
test open/close transitions and accessory-availability loss.

Then a real field protocol: three different ranges, bright sun and dusk, one
deliberately crowded range for false positives, and one 45-minute thermal soak.

**Naming.** "Duo" is Apple's trademark — keep it out of the app name.

**No medical or injury claims**, in the app or on the store listing.

---

## 10. Open questions

1. **Who is building this?** Solo, or a team? It's the single biggest input to
   the schedule in §7.
2. **Down-the-line only for v1, or face-on too?** They need different metrics and
   different framing guidance. Down-the-line alone is a meaningfully smaller
   Phase 2.
3. **Is the coach-facing inner display a feature you want to lean into,** or
   should it just be a settings screen? It's the most distinctive thing available
   to us, but it's also a second UI to design and maintain.
4. **Do you have a Duo on pre-order?** Pre-orders open 16 October. Phase 1 cannot
   start without one, and range testing realistically wants two.

---

## Appendix — sources

- [Apple unveils iPhone Duo (Newsroom)](https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/)
- [Prepare your app for iPhone Duo — Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Strike a pose with adaptive layouts on iPhone Duo — Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Leverage multiple displays and scenes on iPhone Duo — Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Build a great camera experience for iPhone Duo — Tech Talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/)
- [iPhone Duo technical specifications](https://www.apple.com/iphone-duo/specs/)
- [iPhone Duo cameras explained: 48MP Dual Fusion, no telephoto](https://www.macobserver.com/tips/round-ups/iphone-duo-cameras-explained-48mp-dual-fusion-no-telephoto/)
- [iPhone Duo Slo-Mo and Action Mode](https://www.macobserver.com/tips/round-ups/iphone-duo-slo-mo-action-mode/)
- [The iPhone Duo lacks variable aperture and a dedicated telephoto camera (Engadget)](https://www.engadget.com/2254121/the-iphone-duo-lacks-variable-aperture-and-a-dedicated-telephoto-camera/)
