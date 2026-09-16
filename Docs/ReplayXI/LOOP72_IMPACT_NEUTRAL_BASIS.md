# Loop 72 — Impact boot basis and neck blend

## Result

Two existing zero-quaternion targets broke impact animation. The fixes are two explicit unit-identity substitutions; no asset, authored motion, floor-guard, camera, or playback changes.

- Skinned boots now retain the licensed asset's rest basis while the authored ankle rotation is applied. Previously the neutral multiplier erased that basis, turning both boots upward.
- The procedural neck now blends gradually toward neutral during impact. Previously it kept its original look rotation at partial weights, then snapped at full influence.

`simd_quatf()` is the zero quaternion, not the unit identity. Multiplying it by the rest ankle rotation loses that rotation. Using it as a slerp target is also invalid. Both targets now use `simd_quatf(real: 1, imag: .zero)`.

## Evidence and tests

Pre-fix: `/private/tmp/replayxi-parallel72-73-repro-01.xcresult`.
`ReplayImpactNeutralBasisTests`: 3 failed, 1 passed; 15 failed assertions (6 neutral boot axes/bases, 6 authored ankle bases, 3 partial neck blends).

Initial post-fix: `/private/tmp/replayxi-parallel73-full-02.xcresult`.
All 4 impact-neutral tests passed. This whole bundle was not clean: 655 passed, 1 optional skip, and 1 unrelated stale RoomEntry source-string assertion. The root agent updated that assertion to preserve the same physical-entry gate under the new comparison ternary, then reran the full suite. Loop 72 production code and tests were unchanged.

Final full-suite verification: `/private/tmp/replayxi-parallel73-full-03.xcresult` — 657 total, 656 passed, 1 optional skip, 0 failed.

Unsigned physical-device Release: `/private/tmp/replayxi-parallel73-release-01.log` — `BUILD SUCCEEDED`. This is a successful build, not a physical-headset runtime test.

The four tests cover:

- Audited sole-up and toe-forward rest axes; neutral ankle rotation; already-correct arm neutral mapping as a control.
- Actual provider poses at impact +0.25 s, +0.55 s, and +1.5 s, with full influence. Each ankle must compose the authored body/hip/knee/ankle rotations with its source rest basis.
- Exactly unchanged source transforms for zero, negative, NaN, and infinite skin-impact influence.
- Procedural neck and head at influence 0, 0.25, 0.5, 0.75, and 1. For an initial 0.8 rad yaw, the neck now follows the same unit-neutral blend as the already-correct head control.

Before, neutral ankle quaternion agreement with the correct rest basis was 0.56334454 left / 0.43762615 right (about 111.43° / 128.09° error). Sole-up projection was about 0.017749 on both feet; toe-forward projection was +0.247799 / −0.247796. The same missing basis persisted in all three real impact poses.

After, all 8 ankle agreements are at least 0.99999988; neutral sole-up and toe-forward projections are within Float rounding of 1. Arm controls and invalid-influence controls remain passing.

## Eight controlled Blender renders

Unchanged `Scripts/blender/render_runtime_player_poses.py`, Blender 5.2.1 LTS, existing Rocketbox Loop32 Final library, `--frame-body`, 640×800, 24 Cycles samples. No library writes or renderer edits.

The neutral fixture is a synthetic direct-retarget diagnostic at cue start with influence forced to 1. It is not the actual cue-edge runtime influence. The other three samples are actual final provider poses, including its weighted-skin floor correction.

The export uses `groundOffset = -motion.geometry.restMinY` (0.01643639 m), matching the provider's final skin-root offset. Runtime floor correction is already baked into the exported translations; the renderer adds no second correction. These are canonical asset renders, without the player's outer appearance scale.

Full weighted Body + Head mesh minima (5,012 vertices), metres above turf:

| Pose / time | Before | After |
| --- | ---: | ---: |
| Synthetic neutral / 13.55 s | 0.03878839 | 0.00599998 |
| Fall / 13.80 s | 0.15928827 | 0.01656079 |
| Landing / 14.10 s | 0.00600021 | 0.00600021 |
| Settled / 15.05 s | 0.00600069 | 0.00538801 |

All 8 images were inspected. Before: boots point upward in neutral and keep the wrong sole direction in the fall. After: soles and toes follow the intended rest basis and authored bends. No sampled mesh crosses the turf. The settled body rises 0.044403 m because the existing floor guard responds to the corrected boot shape; this is not an added export offset. The full mesh's 5.388 mm minimum is slightly below the contact subset's 6 mm padding but remains clear of the floor.

Derived PNG/report folders:

- `.codex-derived/ReplayXI-Impact72-before-neutral-01` — Blender session 89524, exit 0.
- `.codex-derived/ReplayXI-Impact72-before-authored-01` — session 46295, exit 0.
- `.codex-derived/ReplayXI-Impact72-after-neutral-01` — session 50047, exit 0.
- `.codex-derived/ReplayXI-Impact72-after-authored-01` — session 20902, exit 0.

Native attachment inputs:

- Before neutral: `/private/tmp/replayxi-impact72-before-neutral-01/7E263DF4-BD39-461D-A18E-20AD4D36D4AA.json`.
- Before authored: `/private/tmp/replayxi-impact72-before-authored-01/A860AB95-57F3-4BE7-A68C-D598681D6B95.json`.
- After neutral: `/private/tmp/replayxi-impact72-after-neutral-01/6F3DF27F-A1B7-47B3-A7BE-1CF69F661C2A.json`.
- After authored: `/private/tmp/replayxi-impact72-after-authored-01/82B20A94-B3AE-4A47-9E15-4A78372519E6.json`.

## Scope and limits

Changed: `ReplaySkinnedAthleteImpactPose.swift`, the neck target in `ReplayAthleteMotion.swift`, and new `ReplayImpactNeutralBasisTests.swift`. A nearby read-only audit found no remaining bare `simd_quatf()` constructors in the skinned motion helpers, athlete motion, or ball-rolling helper. Unrelated direct entity-reset code was not swept or replaced.

This corrects deterministic replay poses, not live ragdoll physics. The small render sample is not a guarantee for every pose/appearance. No claim of FIFA quality, physical contact accuracy, headset frame rate, or hardware comfort validation is made.
