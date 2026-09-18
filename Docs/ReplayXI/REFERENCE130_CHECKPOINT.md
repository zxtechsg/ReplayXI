# Reference130 — volley balance and keeper readiness

18 September 2026. Local-only native playback; no scenario IDs or saved-review format changed.

## Implemented

- Raised shots gain bounded trunk lean, counter-turn and asymmetric arm balance. Existing boot targets, hips and contact timing remain authoritative.
- Keepers set to the current ball and react only after an observed opposing shot. A later touch ends that reaction; rewind is deterministic.
- Corrected the inherited inward keeper stance. Added native sole-lane IK using the actual skin's leg lengths for sideways steps. The actual volley fixture checks near/low rigs from 7.35–8.00 s, not only static poses.
- Explicit contacts take priority. Smooth cue boundaries, stale-input protection and shared off-ball suppression prevent animation handover snaps.
- Shot lookup is cached once per recording. Existing rig/LOD limits, meshes and textures are unchanged.

## Evidence and limits

- This remains authored animation, not recovered match mocap or EAFC-level motion. Off-camera routes are still inferred.
- Three public CMU motions were downloaded and inspected, but **not integrated**. See [research](REFERENCE130_RESEARCH.md).
- Safe Blender revision support preserves earlier scenes and the app's scenario identity; 35 Python tests pass.
- An intermediate 22-player Blender export verified 376,640 bone matrices, 9,328 root samples and 1,261 ball samples. Root/ball error at supplied stamps was zero; maximum matrix-element error was `3.82e-6`.
- That intermediate visual review exposed the moving-keeper foot-spacing defect, which was then fixed and regression-tested natively. The `.codex-derived/Reference130/` Blender files and preview frames **predate that final correction**; they are not final-build visual receipts. They were not regenerated to avoid redundant work.
- Native geometry/contact tests are not a headset frame-rate measurement or proof of complete natural motion.

## Final verification

- Final full suite: **1,164 XCTest tests, 2 skipped, 0 failures**, plus 2 passing Swift Testing tests. Result: `/private/tmp/replayxi-reference130-full-02.xcresult`.
- Skips: optional transient asset fixture and opt-in live YouTube embed test. Neither is an animation test.
- Unsigned Release/device build passed: `/private/tmp/replayxi-reference130-device-02.log`. No on-headset performance claim.
- All five studies still admit their 27 planned contacts with no misses and reach their goal checks. Native foot/head/save contact suites pass.
- Final native scene stills were exported to `.codex-derived/Reference130/final-native-stills/`; the volley table frame was inspected. These are audit-camera renders, not close-up motion or headset/UI validation.
- Saved reviews remained byte-identical: SHA-256 `b6ca5f189aeda0cb9b0fa2ecd8ed47f7c435ddb0969bb9e4dc87ff1fd3ccadfb`.
- Normal simulator launch succeeded (PID 97595). User changes in the project signing settings and `Info.plist` were not staged.
