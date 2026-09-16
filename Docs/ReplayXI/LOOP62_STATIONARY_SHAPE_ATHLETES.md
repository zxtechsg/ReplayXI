# Loop 62 — Stationary Shape athletes

## Fixed

Ideal-shape players stood at fixed teaching targets but their limbs still used
the running replay tracks. Their gaze also used the raw origin and heading,
not the body position and direction actually shown.

At 12.5 s, the right-back's raw speed was **5.359 m/s** even though his Ideal
station was fixed at **(31, 29)**, facing **−123.164°** towards the displayed
ball. The presentation now supplies **0 m/s** and that actual body pose to both
the procedural rig and skinned player.

The idle descriptor and stable phase use the original player identity. Small
breathing and scan movements remain time-based; running and travel-based head
motion do not leak into the stationary pose. No per-frame track copies,
resampling arrays, new meshes or extra render instances were introduced.

Only authored Ideal targets receive this override, including the safe overview
shown during tracking loss. Problem, ordinary match/POV and untargeted defenders
keep their raw animation. Shape still disables inferred ball actions. The
existing rear-facing gaze fade, save format and local-only behaviour are unchanged.

## Evidence

- Pre-fix: `/private/tmp/replayxi-shape62-repro-01.xcresult` — Ideal failed
  **53 joint assertions**; Problem-after-Ideal control passed.
- `ReplayShapeAthletePresentationTests` now has **5 cases**: procedural standing
  reference, Problem restoration, skinned standing reference with switch-back
  and exact rewind, ready/lost tracking fallback, and target-only/defender control.
- Actual-source Swift diagnostics confirm stationary speed is zero for RB,
  RW and RCM; untargeted defenders receive no stationary override.
- Combined targeted run: `/private/tmp/replayxi-parallel62-fixed-01.xcresult` —
  **56 passed, 0 failed**, including all five Shape tests and four decision
  alignment tests.
- The skinned-scene test exports six actual scene `jointTransforms` samples
  (three Ideal players at 12.5 s and 14 s) for a bounded offline visual check.
- Follow-up: `/private/tmp/replayxi-ball64-fixed-01.xcresult` — **9 passed,
  0 failed** (all five Shape tests plus four ball-grounding tests).
- Full native suite: **606 passed, 1 optional skip, 0 failed**. Device Release
  build passed. See [batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).
- `git diff --check` passed.

## Offline visual check

The unchanged renderer consumed
`/private/tmp/replayxi-shape62-after/F9A0D765-E559-4F30-9193-EEAE4372DE56.json`
and produced six PNGs plus `report.json` in
`.codex-derived/ReplayXI-Shape62-after-01/`. All six images were inspected.
They show upright resting limbs and small head-pose changes; the near-ball
midfielder looks down while the two farther roles keep a more level gaze.
No running stride or obvious limb/neck distortion appears in these samples.

The full weighted mesh remains **approximately 6 mm above the floor** in all
six poses (5,012 vertices). The renderer uses a common source skin and neutral
body orientation: this checks exported articulation, not on-pitch layout or
per-player jersey appearance. It did not overwrite the source Blender library.

No physical-headset interaction or frame-rate validation is claimed.
