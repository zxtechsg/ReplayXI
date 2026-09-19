# Improvement run 138

Local-only Match Replay and Strategy Analysis. Goal remains active.

## Rotation defaults

Native baseline proves `simd_quatf()` is zero, not identity. Eight remaining
production defaults/reset sites used it: seven annotation/draft/guide locations
and the procedural model builder's default parameter. The imported far-body branch
already repairs zero rotations, but procedural fallback meshes did not.

The native fallback test covers both teams and three LODs. It failed 42 assertions:
six lists of non-unit model rotations plus 18 invalid rotated-forward vectors and
18 zero matrix columns. Importantly, all Entity.convert parent/world span checks
passed. Native conversion can mask the bad raw rotation math; this is not evidence
that every affected visual or collider actually collapsed.

Five annotation baseline tests failed 125 unit/axis assertions. They cover labels,
space circumference targets, crossing-keyframe rails and selected paths, elevation
guides and draft zones under a rotated, nonuniformly scaled parent. Existing world
position and hit-size checks are retained. The old crossing regression explicitly
expected a zero quaternion; it now expects a real unit identity.

The candidate uses explicit identity rotations, preserving all authored positions,
scales, selection rules and hit bounds. Procedural animation/rewind and real
head/neck changes from rest are also tested. The combined native candidate passed
all 61 tests, including both teams/three procedural LODs, annotation transforms,
existing stroke/selection/keyframe tests and all five fresh native ball studies.
Evidence: /private/tmp/replayxi-cycle138-identity-candidate.xcresult.

Baselines: /private/tmp/replayxi-cycle138-rig-baseline.xcresult and
/private/tmp/replayxi-cycle138-annotation-baseline.xcresult.

## Direct annotation handle ownership

Native Store probe confirms mark ID alone cannot distinguish A-preview → cancel →
B-preview → stale A-commit/cancel on the same mark. A token-owned handle API and
controller now protect the matching endpoint and gesture. Authoritative lifecycle
cancellation remains distinct from gesture callbacks; curve/joystick previews
retain their separate ownership. Old cleanup cannot cancel a replacement. A fresh
gesture can recover after authoritative cancellation before deferred view cleanup.

Preview samples stay masked from disk saves. Final coordinates survive reopening,
and all samples form one Undo/Redo step. Too-short samples can recover; invalid
final points restore all keyframes and tracking anchors. Interrupted callbacks
match their input source instead of cancelling whichever gesture is now active.

Initial native batch: 103 tests, zero failures. After tightening the rejected-room
callback, all 50 handle/source-wiring tests passed again. That second batch also
included two deliberately failing render-budget baseline tests, recorded below.
Evidence: /private/tmp/replayxi-cycle138-handle-candidate.xcresult and
/private/tmp/replayxi-cycle138-budget-baseline-handle-v2.xcresult.

SwiftUI DragGesture exposes time and starting position, but no native stable
gesture identifier. Source/target/start/time checks and a per-gesture token can
reject old events; indistinguishable reassigned native events are not claimed to
be solved. Reset-before-end, missing-end cleanup and deferred old cleanup have
explicit controller tests. Native user gesture behaviour remains unverified while
the Mac is locked; these tests do not replace headset interaction checks.

## Animated annotation budget

Native baseline confirms four zones with ground → raised → ground keyframes
were admitted using their base elevations. At raised/interpolated frames this
enabled 24 annotation models against the normal 18-model budget. Both reverse
seeks and selected-overlay reservation checks reproduce the mismatch: two tests,
40 assertion failures. Selected actual model counts still fit in these fixtures;
their conservative reservations, not actual counts, exceeded 24.
Evidence: /private/tmp/replayxi-cycle138-budget-baseline-captures.
These are enabled ModelComponent counts, not measured GPU calls or headset FPS.

Admission now uses the existing absolute keyframe sampler for current elevation;
static marks retain their fast path. No new cache or scene-tree rebuild. Four
native regression tests pass, including interpolation/reverse, selected reserves,
decision mode, held keyframe endpoints and single-guide thresholds. Raised normal
zones now admit three (18 models), and ground zones admit four (16 models).
Entity identities remain unchanged across admission changes. All 41 tests in the
combined budget/motion candidate batch pass. Evidence:
/private/tmp/replayxi-cycle138-budget-motion-candidate.xcresult and
/private/tmp/replayxi-cycle138-budget-candidate-captures.

## Foot contact investigation

Cycle137's 10.61 m/s near-floor peak is not proven planted skating. At fra-22's
6.875-second right-boot sample, the source run clip is in forward swing while the
authored procedural gait treats that foot as loaded. The cut overlay is fading.
Floor proximity alone mixes incompatible support/swing phases.

The imported-asset-gated fix aligns the entire authored cut pose by 120 degrees
of gait phase, including opposite arms and torso. Smooth speed admission blends
complete fixed-phase poses; it does not change the source animation or integrated
gait clock. Existing contact preparation fades it out, and protected contact cores
stay exact. Goalkeepers, teaching/impact/stationary overrides and unmatched assets
are excluded. There is no world-space foot lock or new tracking-data claim.

Native same-frame A/B results, near and low-detail models, 120 Hz windows:

| Player/window | Peak joint step, degrees | Peak horizontal sole speed, m/s |
| --- | --- | --- |
| fra-22, 6.80–7.15 | 7.896 → 7.462 | 12.785 → 11.423 |
| arg-10, 1.20–1.65 | 19.307 → 19.058 | 22.116 → 14.014 |
| fra-5, 11.192–11.342 | 7.996 → 9.249 | 11.327 → 11.084 |
| arg-13, 6.825–6.975 | 12.307 → 10.194 | 8.694 → 8.694 |
| city-11, 4.125–4.275 | 5.803 → 5.501 | 8.813 → 8.302 |

The fra-5 joint-step regression is retained as an explicit trade-off, not hidden
by a global mean. Near-floor subsets also change sample membership: fra-22 peak
10.612 → 8.059 m/s but sample count 24 → 20; other windows' near-floor means can
increase. Authored source-support markers are not measured foot force, and this
is not a universal skating fix. Calibrated native captures show a less crossed
stance at fra-22 6.875; screenshots alone cannot establish motion quality.

Bone lengths, floor clearance and reverse evaluation pass. The arg-10 protected
core has 12 byte-exact samples per LOD; its independent unaligned full-window
hashes still match the earlier baseline. Phase-wrap, zero/partial/full admission
and opposite-arm pairing tests also pass. Evidence:
/private/tmp/replayxi-cycle138-phase-candidate-captures and
/private/tmp/replayxi-cycle138-budget-motion-candidate.xcresult.

The 30 Hz policy scan covers 33,770 player samples: 1,230 admit alignment and
1,086 request a second authored pose. This is a policy-work estimate assuming
active locomotion, not observed provider calls, CPU cost or FPS. Zero/full
admission evaluates only one authored pose. Production override/LOD/cache paths
can change actual work.

All five fresh native ball records retain 27 contacts, zero misses and 6,125
samples. Their full position/velocity trajectories and touch records are JSON-
exact against the cycle137 baseline. Evidence:
/private/tmp/replayxi-cycle138-ball-candidate-captures.

## Final validation and remaining work

- Full native suite: 1,359 XCTest tests, two intentional skips, zero failures;
  both Swift Testing imported-asset checks also pass. Skips are the unstaged
  transient Rocketbox fixture and opt-in network YouTube embed check.
  /private/tmp/replayxi-cycle138-full.xcresult and .log.
- Unsigned visionOS device Release build passes. The only build warning is the
  unused AppIntents metadata-extraction notice; no Swift build errors/warnings.
  /private/tmp/replayxi-cycle138-release.log.
- Final native phase receipts, including the provider-wiring gain assertion and
  qualified work estimate: /private/tmp/replayxi-cycle138-phase-final-captures.
- Latest normal simulator app relaunched; saved reviews remain SHA256
  952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65.
- Hands-on UI/gesture validation is still pending because the Mac is locked.

Next bounded motion investigation: attribute the remaining arg-10/fra-5 peak to
an exact joint and time, with native snapshots before/after retarget, contact/look
and floor stages. Existing receipts contain only final-window maxima; they do
not identify the peak joint. Raw source steps alone do not explain those maxima.
Do not relax protected-contact checks merely to reduce a summary metric.

Goal remains active. Unrelated user project/Info.plist edits are preserved.
