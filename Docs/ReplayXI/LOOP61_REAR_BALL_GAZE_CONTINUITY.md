# Loop 61 — Rear-ball gaze continuity

## Fixed defect

A ball crossing directly behind a player flipped the signed relative bearing from +180° to −180°. Clamping each side to ±112° then applying ball attention drove the head abruptly between opposite shoulder checks.

The native regression used a stationary track, fixed timestamp, and ball bearings 179.994° and 180.006° at 10 m: only 2.1 mm of target movement. The same crossing was also tested at running effort.

| Measurement | Before | After |
| --- | ---: | ---: |
| Idle, combined neck/head yaw change | 128.000° | <0.00006° |
| Run effort 3.6 m/s, combined yaw change | 110.000° | <0.00006° |
| Idle, actual skinned head rotation change | 127.903° | Below float-angle measurement resolution |
| Run, actual skinned head rotation change | 109.994° | Below float-angle measurement resolution |
| Combined pitch in all crossing fixtures | 0.0960783884 rad | Exact same value |

This was a target-bearing discontinuity, not an accumulated or doubled neck rotation.

## Small production change

`ReplayAthleteMotion.lookPose` retains the unclamped relative ball bearing. Horizontal ball attention remains unchanged through ±112°, then fades smoothly to zero at ±180°. No previous-frame state is introduced.

Unchanged: forward/side ball attention, head pitch, deterministic scan, neck/head split, source neutral axes, clavicle compensation, source gait, floor guard, free-look camera, assets and licence records. Gaze remains a generated estimate, not measured eye tracking. This fix does not claim to reconstruct what a real player saw.

## Native verification

Six tests in `ReplayAthleteGazeContinuityTests` cover:

- Rear crossings at four root headings and four speeds.
- 5,776 dense azimuth samples, including rear wrap and side-sector joins.
- Explicit ±112° and ±180° boundary checks.
- Repeated and reversed timestamp order.
- Existing front/side attention weights, pitch and cervical shares.
- Actual skinned neck/head composite rotation, shoulder isolation and repeat pose equality.

Pre-fix: **4 failed, 2 passed**, with expected rear-continuity failures.

`/private/tmp/replayxi-gaze61-repro-01.xcresult`

Post-fix: **36 passed, 0 failed**, including all six new tests plus existing rig and facing coverage.

`/private/tmp/replayxi-gaze61-fixed-01.xcresult`

Runtime pose exports:

- Before: `/private/tmp/replayxi-gaze61-before/F8E0756D-823D-45CB-AE80-F9BD5C9EEFF3.json`
- After: `/private/tmp/replayxi-gaze61-after/C4820492-84A3-4BDE-B61F-92B45012E8B1.json`

The front and side control frames have exactly equal complete native poses. Rear-frame changes are confined to neck/head rotations and the existing compensating clavicle transforms. Root, gait joints, scales and jersey anchors were not changed by this fix.

## Blender evidence

The existing renderer applied the eight exported native poses before and after to the same licensed source skin. No source asset or renderer was edited.

- Before gallery: `.codex-derived/ReplayXI-Gaze61-before-01/`
- After gallery: `.codex-derived/ReplayXI-Gaze61-after-01/`
- Each gallery contains eight PNGs and `report.json` with full weighted-mesh bounds.

The idle and run rear-crossing pairs were visually inspected on both sides of the fix. Before, the head visibly flips while the body holds the same pose. After, the head remains visually steady. Both front/side control images have identical decoded RGB pixels before and after; PNG metadata differs.

| Pose group | Full-mesh minimum above floor, before and after |
| --- | ---: |
| Idle rear left/right/repeat | 6.000077 mm |
| Run rear left/right/repeat | 7.107018 mm |
| Idle front/side controls | 6.000077 mm |

All 16 full-mesh floor minima are unchanged. The running recovery/flight pose is preserved.

## Scope and limits

No headset or unlocked Simulator UI inspection was possible. Native tests and offline Blender skin renders establish this bounded correction; they do not establish headset frame rate or comfort in a live session. No full-suite or Release receipt is asserted for this batch here.

The separate Shape Ideal presentation/telemetry mismatch is tracked in Loop 62, not changed or counted as fixed in Loop 61.
