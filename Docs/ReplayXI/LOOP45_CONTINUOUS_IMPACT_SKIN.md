# Loop 45 — continuous player skin during impacts

## Changes

- The near-player skin now stays visible through the existing fixed-step impact
  cue. Root, torso, head, arms and legs are retargeted in model space, then
  recovered into the source Biped hierarchy. Face/finger motion stays sampled.
- The visible skin and hidden kinematic query body share one absolute-time
  solver sample. The query body still updates while its old mesh is hidden.
  Source timestamps and player IDs are checked before a skin accepts a sample.
- External review views admit the impact subject alongside the selected player
  (at most two skins). Player POV still caps detailed neighbours at two, hides
  the wearer, and does not add a camera roll or automatic impact opt-in.
- Corrected a reversed elbow hinge in the procedural gait and impact mappings.
  Arms now flex forward, not behind the upper arm. The licensed source run clip
  was already oriented correctly and remains unchanged.
- A two-bone contact adjustment lets a low arm fold without lifting the entire
  torso. Transporting its bend plane avoids a forearm twist at first contact.
- A small support envelope prevents deep ground penetration. It is an
  approximation, not a complete body-to-mesh contact solver.
- Non-finite solver timestamps cannot reach `Int(NaN)` in the fixed-step loop.
- The existing Blender runtime-pose QA tool now includes the head surface,
  semantic-joint positions and optional full-body framing for falls.

## Verification

- New impact tests: **9 passed**, no failures/skips. Cover eight push directions,
  cue/recovery edges, body proportions, exact rewind, jersey anchors, query-body
  updates, skin/LOD limits, invalid timestamps, stale samples and buffer reuse.
  `/private/tmp/replayxi-impact45-targeted-06.xcresult`.
- Full Simulator suite: **436 passed, 1 optional skip, 0 failed (437 total)**.
  `/private/tmp/replayxi-impact45-full-01.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-impact45-release-02.log`.
- Python checks: **107 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-impact45-python-02.log`.
- `git diff --check` passed. No signing/project edits included in this batch.
- Eight actual runtime poses rendered against the existing Blender library:
  `.codex-derived/ReplayXI-ImpactPose45-final/`. The source library was not changed.
  Rewind and jersey placement are also tested on the actual imported skin.

The first visual pass exposed whole-body lift from the arm envelope. The first
contact adjustment exposed a forearm twist. Both were corrected before the
successful full run; earlier diagnostic result bundles retain those failures.
An initial test expression also needed simplification for Swift's type checker.

## Remaining limits

This is the licensed Rocketbox body plus authored/replay-safe articulation, not
FIFA assets, football mocap, or an unconstrained game-physics ragdoll. The final
renders still show a conservative 6–9 cm ground gap at the land/settled samples;
the late recovery sample has about 6 mm of boot-surface penetration. Next work
should calibrate support to the actual skin surface instead of enlarging the
proxy envelope. Recovery is still a blend back to telemetry, not a captured
stand-up animation. Physical-headset comfort and frame rate are not measured.

Direct desktop UI checks remain unavailable while the Mac is locked. Background
Simulator tests and Blender renders are not a substitute for hand/click tests.
The reference match is still synthetic; no supplied real clip was reconstructed.

The timed goal remains active. This is a verified backup, not the 9am handoff.
