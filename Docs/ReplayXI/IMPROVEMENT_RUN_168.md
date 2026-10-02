# Cycle 168 — neck/head motion

Scope: native player animation in local replay. No new assets, cloud generation,
saved-review format, playback UI, or physics changes.

## Changes

- Ordinary gaze now blends the rendered head towards its intended direction in
  the player's root frame. This reduces unwanted chin tilt inherited from the
  running chest. Source roll and part of the source animation remain.
- The correction is shared by neck and head instead of bending only the skull.
  Legacy Biped clavicle branches are compensated so gaze does not pull the arms.
- A close ground ball no longer holds the player in a deep downward glance.
  The adjustment fades with ball distance/height and contact protection.
- Fixed a separate gaze jump when the ball crosses the player's position:
  travel attention and scan strength now enter continuously with visibility.
- Kicks/headers at their protected contact cores, keeper motion, stationary
  poses, impacts and invalid targets retain the previous final constraint path.
  Existing chest-relative limits remain 70° yaw, 40° pitch and 22° roll.
- The neck subtree is cached once. The Tripo correction rebuilds two joint
  matrices, not the full 52-joint skeleton. The Biped fallback also rebuilds its
  compensated descendants. This is not a measured FPS improvement.

## Reference and limits

The FIFA final reference was inspected at video 5,440 s (game 80:41): Messi's
head is mostly upright while carrying. That supports reducing a sustained
downward glance; it does not provide measured joint angles. At video 5,450 s,
the wide shot cannot resolve exact head direction.

[FIFA reference](https://www.youtube.com/watch?v=RgqKdplLIk4&t=5440s).

All five existing scenario sources remain unchanged. This cycle does not add
motion capture, eye tracking, new camera angles or frame-matched head tracks.
Off-camera movement and gaze remain inferred. Cloth, hand poses and some fast
target changes still need work; this is not EAFC-level animation.

## Validation

- visionOS 26.5 Simulator: **174 selected tests passed**, zero failures/skips.
  Bundle: `.codex-derived/replayxi-head168/Regression265-01.xcresult`.
- Re-ran both `ReplayHeadAim168Tests` after adding the existing 12°/frame
  cervical safety envelope to the five-demo diagnostic: **2 passed**.
  Bundle: `.codex-derived/replayxi-head168/FinalGuard265-01.xcresult`.
- Both unsigned Release builds passed: visionOS device and Simulator.
  Logs: `/private/tmp/replayxi168-device-release.log` and
  `/private/tmp/replayxi168-simulator-release.log`. No headset run or FPS test.
- Native tests cover Tripo near/low plus Biped fallback; both teams; arm/leg
  preservation; protected contacts; headers/saves; impacts; gaze seams;
  reverse/exact seeks; scrubbing; review persistence and annotation undo/redo.
- Four close-up native renders inspected. The A/B switch isolates shared
  cervical aiming; both images already include the ground-ball gaze rule.
  [Home control](Evidence168/home-control.png) / [updated](Evidence168/home-aimed.png),
  [away control](Evidence168/away-control.png) / [updated](Evidence168/away-aimed.png).
  Visible cloth/hand artifacts remain unchanged.
- Main Simulator saved-review SHA-256 remains
  `a472d19ff9b2f3495dab0b38d98c306dddfed2e2e0493c8a450ce82f4e9b18cb`.
  Tests/install used the separate `ReplayXI Native Audit 26.5` Simulator.
  Release app launched there. Both USDZs and source motion JSON are unchanged.
- `git diff --check` passes. User-owned project/signing changes are excluded.

## Measured scope

Across 450 sampled poses (five short demo windows, two players each, three rig
variants), 420 adjacent model-space head steps average **1.218° → 0.969°**.
Nearest-rank p95 is **3.017° → 2.187°**. These narrow windows are not a full
match or ground-truth animation-quality score.

The worst sampled step increases **7.441° → 7.832°** in the rebound at 2.033 s.
The intended gaze already changes 7.608° there; the new aim follows it more
closely. Do not claim every frame is smoother. Further work should address
that fast target change without breaking absolute-time seeking.

In the sampled Tripo near windows, mean pitch is **11.22° → 5.39°** for arg-11
(intended 2.24°) and **10.51° → 2.59°** for fra-10 (intended −1.67°). Those
intended values are app gaze, not video measurements. The independent
[ordinary-aim A/B data](Evidence168/ordinary-aim-ab.json) records both cervical
joints moving while the native tests verify other branches stay fixed.

[Validation metadata](Evidence168/validation.json).
