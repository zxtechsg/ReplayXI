# Loop 46 — ground contact from the actual Blender skin

## Changes

- Replaced the enlarged impact-support spheres with **339 actual skin vertices**
  and **603 weighted influences**, shared across player instances. The body has
  5,012 vertices; no full-mesh readback or per-frame asset decode is needed.
- Bone-local contact points are prepared at asset load. Impact posing queries
  their weighted height, settles a landed body onto that surface and preserves
  the airborne part of the fall. Recovery stays on the existing replay clock.
- The 33,957-byte profile is hash-checked and tied to the shipped body and motion
  hashes. The decoder bounds payload size, vertex/influence counts, positions,
  IDs, padding and weight normalization. An invalid asset still fails softly
  to the procedural player rather than crashing playback.
- `Scripts/blender/build_player_contact_surface.py` reads the audited library
  without changing it. It selects neutral extrema, then adds missed contact
  vertices from runtime poses and all source idle/run frames. Generated files
  must go into a new directory below `.codex-derived`; the source library hash
  must match. Use Blender's `--python-exit-code 1` in automation so script errors
  are returned as process failures.
- The third-party asset ledger includes this MIT-derived contact profile.

## Calibration and visual evidence

- **206 poses**: 96 impact-direction/strength/phase samples, eight demo samples
  and 102 source idle/run frames. Maximum omitted contact depth: **2.994 mm**.
  A **6 mm** pad leaves room for the sampled-surface approximation.
- Full linear-skinning calculation agreed with evaluated Blender skin to within
  **0.00072 mm** at the checked minima. This verifies coordinates and weights,
  not physical-headset frame timing.
- A clean rebuild produced the exact bundled SHA-256:
  `71eb134afa27eac0c23500afbd038dd11594a2b5ad30a5a178b303305a49c3ca`.
- Receipts: `.codex-derived/ReplayXI-ContactSurface46-v2/report.json` and
  `.codex-derived/ReplayXI-ContactSurface46-repro/report.json`.
- Actual runtime poses rendered in `.codex-derived/ReplayXI-ContactPose46-final/`.
  The landing and settled surface gaps decreased from **60/91 mm to 6/6 mm**.
  Late-recovery boot penetration decreased from **5.86 mm to 0.12 mm** in the
  checked sample. The after-cue source-run sample is unchanged at about 1.71 mm
  penetration; this batch changes impact contact, not the whole gait solver.

The initial neutral-only candidate set missed an articulated low point by
30.5 mm. The exporter rejected it; motion calibration was added before packaging.

## Verification

- Contact/impact targeted suite: **15 passed**, no skips/failures.
  `/private/tmp/replayxi-contact46-targeted-02.xcresult`.
- Final full Simulator suite: **442 passed, 1 optional skip, 0 failed (443 total)**.
  `/private/tmp/replayxi-contact46-full-01.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-contact46-release-01.log`.
- Python pipeline checks: **107 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-contact46-python-01.log`.
- Tests cover exact weighted transforms, root translation, malformed profiles,
  resource identity, eight fall directions, contact height, smooth edges,
  rewind, buffers, jerseys, physics proxies and near-player limits.
- `git diff --check` passed. User signing/project edits remain separate.

## Limits

The profile is calibrated for this rig and motion set, not every possible future
pose. Different bodies or animations need fresh calibration. There is no captured
get-up clip, live full-body collision solver or measured headset FPS claim.
The Mac remains locked for direct UI/hand tests; background Simulator tests and
Blender renders do not prove physical interaction or comfort. The match remains
synthetic because a usable reference clip has not been supplied.

The timed goal remains active. This is a tested backup, not the 9am handoff.
