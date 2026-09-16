# Loop 80 — Near-idle path confidence

## Finding

The residual keeper transition after Loop 76 is smooth but fast. It is not another binary discontinuity, non-finite pose, rig swap, or measured tracking error. A brief extra head reversal remains because path curvature can outweigh authored body facing while the player is nearly stationary.

This is a bounded presentation refinement for the synthetic demo. It does not establish that the existing turn is physically impossible or that a headset user experiences jitter.

## Exact native diagnostic

`ReplaySlowdownWindowDiagnosticsTests` passed in `/private/tmp/replayxi-parallel78-80-repro-01.xcresult`. It captures 27 samples per window at 5 ms spacing, plus 8 selected actual skin poses:

- Keeper: red-gk, 26.46–26.59 s.
- Standing control: red-gk, 10.00–10.13 s.
- Running control: navy-rb, 12.10–12.23 s.

Both renderers use the same telemetry, ball, action and gaze inputs. Native head/neck quaternions include the player's authored facing rotation. The comparison baseline disables only the turn cue; it keeps source animation, ball attention, body motion and breathing. Every sampled quaternion is finite/unit, and a repeated start seek reproduces the skin pose exactly.

Keeper window:

- Speed: 0.079986–0.199522 m/s, within the existing idle classification.
- Body travel: 7.980 mm cumulative, 1.652 mm net; maximum 0.768 mm per 5 ms.
- Authored facing increases 4.813957°; ball bearing increases 4.378284°. The ball moves 184.678 mm smoothly.
- Turn signal ranges from −105.971573 to +56.117474°/s.
- Skin head yaw travels 16.760895° for a net 9.376541° change. The excess includes a 3.692177° reversal. Its baseline is monotone: 8.109421° total and net.
- Procedural head yaw similarly travels 17.055336° for a net 9.104790° change; baseline total and net are 7.821426°.

Maximum rotation between adjacent 5 ms samples, degrees (each column is its own window maximum):

| Keeper joint | Actual | Turn-disabled baseline |
| --- | ---: | ---: |
| Skin head | 2.771222 | 0.422847 |
| Skin neck | 1.289761 | 0.341308 |
| Procedural head | 2.747511 | 0.421531 |
| Procedural neck | 1.288821 | 0.341179 |

The largest actual head step ends at 26.545 s. The skin value corresponds to about 554°/s over that interval; this is a measured presentation rate, not a physiological acceptance limit.

Standing control maxima: skin head 0.047805°, procedural head 0.040967°, identical to their respective turn-disabled baselines. Running control maxima: skin head 0.247918° (baseline 0.247487°), procedural head 0.115920° (baseline 0.119766°). Source-animation motion is therefore distinct from the keeper's near-stop curvature response.

Native export: `/private/tmp/replayxi-window80-diagnostic-01/3429791A-4E3F-4A20-8BF6-0E9E0F491B79.json`. Numeric summaries above are derived from those native quaternions/positions, not a separate animation model.

## Approved minimal refinement

Multiply only path-turn confidence by a continuous speed weight: zero at or below 0.18 m/s, full at or above 0.40 m/s, cubic smoothstep between. Keep authored facing turns and the Loop 76 cue combination unchanged.

The lower boundary matches the existing start of moving attention in gaze. The upper boundary retains full path confidence for the existing 0.4512 m/s planted-turn control and faster motion. These are explicit presentation-policy choices, not recovered real-world gaze or physiological constants.

The change adds only the speed-confidence multiplier to the existing bounded path cue. No asset, skeleton, floor-guard, camera, keyframe, save schema, or mutable animation history changes were made.

`ReplayLowSpeedPathConfidenceTests` adds four focused cases: low-speed authored-facing preservation for both turn signs; continuous joins plus a 101-point monotone/reverse band; confident moving and body-only controls; exact skin/procedural head equality to the authored-facing cue at six measured near-stop times. The existing diagnostic and Loop 76 thresholds remain unchanged.

Pre-fix native receipt: `/private/tmp/replayxi-parallel78-82-mixed-01.xcresult` (log with the same stem). Three policy cases failed with 46 assertion failures: 24 actual-head comparisons, 16 low-speed cue comparisons, and 6 join/strength comparisons. The confident-moving/body-only policy control and the unchanged diagnostic passed. These failures establish the new presentation policy, not a newly discovered binary discontinuity. The production patch followed this receipt; no test or tolerance was relaxed.

## Post-fix native result

All four policy tests and the unchanged diagnostic pass in `/private/tmp/replayxi-parallel80-84-mixed-01.xcresult`. This mixed bundle also includes unrelated pre-fix text-layout failures; it is not a clean full-suite receipt. Swift parse and the scoped diff check pass.

After export: `/private/tmp/replayxi-window80-after-01/63C43612-0281-4DD4-8E47-C5C280E827AB.json`. The same exact native windows produce:

| Keeper joint | Before maximum / 5 ms | After maximum / 5 ms |
| --- | ---: | ---: |
| Skin head | 2.771222° | 0.481249° |
| Skin neck | 1.289761° | 0.365986° |
| Procedural head | 2.747511° | 0.478690° |
| Procedural neck | 1.288821° | 0.365802° |

Both head yaw sequences are now monotone. Skin yaw total travel is 9.376541°, equal to its unchanged net change; the former 3.692177° extra reverse swing is absent. Procedural yaw travel is 9.104790°, likewise equal to its unchanged net change. The largest remaining head step occurs at 26.59 s, not the former path-cue reversal at 26.545 s.

All 27 standing rows and all 27 running rows are exactly identical before/after, including their head/neck quaternions. Keeper position, speed, facing, ball, and turn-disabled baselines are also unchanged. The revised cue still feeds the existing whole-body animation, not only gaze: three exported keeper samples have small limb/root changes, with maximum local translation difference 2.374 mm. Skeleton structure, rest axes and the floor guard are unchanged.

## Before/after render audit

Eight exact native poses were rendered before into `.codex-derived/ReplayXI-Window80-current-01` (session 22237) and after into `.codex-derived/ReplayXI-Window80-after-01` (session 3184), using the unchanged Blender script/library. Both jobs exited 0; all 16 stills were inspected. The keeper direction change is subtle in stills; the native time sequence supplies the rate evidence. Standing and running poses remain distinct and exactly unchanged. No sampled weighted mesh crosses the turf.

Full weighted Body + Head minima (5,012 vertices), metres above turf:

| Pose | Before minimum | After minimum |
| --- | ---: | ---: |
| keeper-window-0 | 0.00600008 | 0.00600008 |
| keeper-window-4 | 0.00600000 | 0.00600000 |
| keeper-window-8 | 0.00599965 | 0.00599975 |
| keeper-window-13 | 0.00599999 | 0.00599999 |
| keeper-window-17 | 0.00599992 | 0.00600013 |
| keeper-window-21 | 0.00599977 | 0.00599977 |
| standing-window-0 | 0.00600000 | 0.00600000 |
| running-window-0 | 0.04518601 | 0.04518601 |

As in previous rig QA, these are canonical library-mesh renders, without final player kit/appearance scale or the scene's world-facing transform. Final runtime grounding is already in the exported pose; only the actual skin-root offset is added by the renderer.

## Limits

This diagnostic does not show another discontinuity. It supports reducing a rapid, unnecessary near-idle path-driven reversal as a presentation refinement. Stills and native pose sampling do not replace playback inspection on Vision Pro, establish headset comfort, or measure hardware frame rate. Real player gaze remains unknown.
