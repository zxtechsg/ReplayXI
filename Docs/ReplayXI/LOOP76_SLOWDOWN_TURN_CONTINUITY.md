# Loop 76 — Slowdown turn continuity

## Defect

The authored 32-second demo could produce a sharp head change while a player was almost stationary. This was not a source animation-loop seam or a rig swap.

`PlayerTrack.locomotion(at:)` admitted the path direction abruptly when each 120 ms half-window exceeded 5 mm of travel. Crossing that threshold could introduce a full ±360°/s cue. A second hard choice selected whichever of path turn or authored facing turn had greater magnitude. Opposite cues therefore flipped sign when their magnitudes crossed.

These are animation estimates from the synthetic demo, not captured head motion. The cue also contributes directly to gaze lead.

## Native reproduction

`/private/tmp/replayxi-parallel74-77-repro-01.xcresult`:
3 new tests failed, 2 control tests passed. There were 10 failed assertions: 9 product assertions and 1 invalid fixture premise.

Retained 5 ms pairs all move the body under 6 mm and change authored facing under 0.5°. Native turn-signal jumps:

| Player / timestamps | Before, °/s | After, °/s |
| --- | ---: | ---: |
| navy-rcm, 13.490 → 13.495 | 359.817871 | 0.016589 |
| red-gk, 26.480 → 26.485 | 391.933533 | 0.689524 |
| red-gk, 26.560 → 26.565 | 409.588104 | 1.239029 |
| navy-rw, 12.610 → 12.615 | 108.282745 | 13.999775 |
| navy-rw, 12.925 → 12.930 | 110.613861 | 4.244205 |
| navy-cf, 26.710 → 26.715 | 133.080383 | 3.067711 |

The actual keeper skin at 26.560 → 26.565 s rotates its neck 4.324045° and head 10.246923°. The same source animation, ball target, breathing and gaze with only turn disabled changes them 0.055953° / 0.137056°. This isolates the visible fault from ordinary animation.

The midfielder pair is different: its existing gaze limit masks the bad signal, so actual neck/head change is only 0.104678° versus the control's 0.096913°. It is a signal regression and a visual control, not evidence of a second visible head snap.

After the fix, the keeper's actual neck/head changes are 0.104678° / 0.193827°, with the same control baselines. The midfielder's actual neck/head changes are 0.096913°. These angles come from native exported joint matrices, not the Python study.

Fixture correction: the redundant navy-rcm 13.570 → 13.575 s pair had raw input change 66.079834°/s, exceeding its own <60°/s premise. It was removed with approval, not given a looser limit. That also removes one redundant product failure. The keeper still covers gate exit; all retained input, turn and skin thresholds are unchanged.

## Small fix

Only the turn-estimator block in `FootballModels.swift` changes:

- Bound the path cue to ±360°/s before applying smooth confidence over 5–25 mm of travel in both half-windows.
- Keep the strongest cue when both have the same sign. Pure path turns retain their previous response when confidence is full, as in the planted controls; very slow path turns are deliberately attenuated. Stationary body-only turns remain unchanged.
- Blend opposing cues using normalized squared magnitudes, so equal strength joins through zero instead of switching sign abruptly.

There is no mutable history, new trajectory sampling, array allocation, keyframe rewrite, schema change, or Factory edit. Gait phase, speed, acceleration, source clips, floor guard, ball tracking, free-look and camera behavior are unchanged.

## Verification

`ReplayLocomotionTurnContinuityTests` contains 5 tests: exact slow-gate pairs; opposed-cue pairs; actual skinned head/neck output; planted, straight and stationary-turn controls; and finite/unit/positive-scale/exact reverse-seek checks. The turn tolerance is twice the larger measured input change plus 5°/s. It does not require a desired sign. The skin tolerance is the measured turn-disabled baseline plus 1° over 5 ms.

Post-fix native verification: `/private/tmp/replayxi-parallel77-full-01.xcresult` — 676 total, 675 passed, 1 optional legacy-asset skip, 0 failed. All 5 Loop 76 tests and the existing track/facing/skin controls passed.

Unsigned physical-device Release: `/private/tmp/replayxi-parallel77-release-01.log` — `BUILD SUCCEEDED`. Python checks: `/private/tmp/replayxi-parallel77-python-01.log` — 126 total, 114 passed, 12 optional skips, 0 failures. These build/test receipts do not represent a physical-headset runtime session.

A read-only source-math study scanned all 22 tracks at 5 ms spacing: 140,822 samples. The largest turn step fell from 409.588 to 55.409°/s. The remaining maximum is a continuous confidence transition near keeper 26.54 s, not the old binary gate. All retained pair bounds and planted ±360°/s / stationary 45°/s controls pass that study. These are Python double-precision calculations, not authoritative native Float or headset measurements.

The same read-only asset audit found idle/run first-to-last local-joint differences below 0.022°, translation changes below 0.55 µm, and scale changes at most 5e−7. No visible source-clip loop reset was demonstrated.

## Controlled render evidence

The unchanged Blender renderer uses the existing licensed Loop32 Final library and actual final provider transforms, including runtime grounding. Exported `groundOffset = -restMinY` matches the skin root; no extra floor correction is added. The canonical home mesh/jersey is used for rig QA, not the keeper's final kit or outer appearance scale.

Before gallery: `.codex-derived/ReplayXI-Turn76-before-01`; Blender session 28083, exit 0. After gallery: `.codex-derived/ReplayXI-Turn76-after-01`; session 45385, exit 0. Both use the same four views at 640×800 / 24 samples. All 8 images were inspected. The keeper's before pair shows a head-direction change with nearly fixed body; its after pair holds nearly the same head direction. The midfielder remains visually stable. Full weighted-mesh minima (5,012 vertices):

| Pose | Before, m | After, m |
| --- | ---: | ---: |
| midfielder-slowdown-a | 0.00599976 | 0.00599976 |
| midfielder-slowdown-b | 0.00599995 | 0.00599968 |
| keeper-slowdown-a | 0.00599990 | 0.00599983 |
| keeper-slowdown-b | 0.00599977 | 0.00599977 |

No sampled weighted mesh crosses the turf. Native exports:

- `/private/tmp/replayxi-turn76-before-slowdown-01/8711E597-0AE4-476E-AC7D-BE01267E8A54.json`
- `/private/tmp/replayxi-turn76-before-opposed-01/206B7A55-9030-4C97-9631-37734E009D7E.json`
- `/private/tmp/replayxi-turn76-before-skin-01/C68F4FAC-3B0B-4E67-861E-D77EA0134D13.json`
- `/private/tmp/replayxi-turn76-after-slowdown-01/806CAB05-AE06-4773-981C-B6FBDEE4F415.json`
- `/private/tmp/replayxi-turn76-after-opposed-01/38B48BC5-6808-46D7-ABEC-3C5194A8E7A9.json`
- `/private/tmp/replayxi-turn76-after-skin-01/B314930D-3178-45CA-809A-257154E6AAE8.json`

## Limits

This fixes discontinuous presentation cues; it does not infer real gaze or reconstruct motion capture. The remaining continuous transition may still look fast at some timestamps. Sampled still renders do not establish animation quality across every frame, headset comfort, or hardware frame rate. No asset, renderer, licensing, or camera changes were made.
