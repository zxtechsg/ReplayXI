# Loop 86 — Bounded run-contact measurement

## Scope

Measurement only. No animation, asset, trajectory, scale policy or camera changes. Near-turf motion is evidence, not automatically physically invalid sliding: a foot can roll, and a changing lowest vertex is not a stable material point.

## Code findings before measurement

- The licensed run clip has 19 frames over 0.600 s. Its source X/Z root motion was removed; source vertical motion remains.
- `PlayerTrack.gaitPhase(at:)` integrates a deterministic segment-speed cadence, `0.58 + 0.38 * sqrt(min(speed, 10))` cycles/s. This is the current authored presentation rule, not a measured player cadence.
- The clip is remapped to that phase. Straight movement above 2.25 m/s with a turn cue below 38°/s and no ball action retains the source leg cycle. The retargeter's walking/cut/action influence is also recorded directly.
- The final weighted-skin floor guard is vertical only. There is no source stride-length calibration or horizontal contact lock. This makes mismatched world foot movement plausible, but does not by itself prove a visible defect.
- The existing procedural sprint test measures an authored synthetic track, using footfall confidence and boot-bounds centre. It does not measure the licensed skin on these demo tracks.

## Native diagnostic plan

`ReplayRunContactDiagnosticsTests` captures four fixed 0.8 s windows at 120 Hz, 97 samples each, 388 rows total:

| Window | Player | Time |
| --- | --- | --- |
| Overlap jog | navy-rb | 6.85–7.65 s |
| Overlap run | navy-rb | 11.60–12.40 s |
| Recovery run | red-lw | 13.55–14.35 s |
| Standing control | red-gk | 10.00–10.80 s |

Each sample uses the actual final native skin pose and actual procedural near/mid/far entity poses. The real per-player appearance scale and model hierarchy transform the geometry into a pitch-local world frame. Match-scale focus is 1, as for visible first-person neighbours; enlarged table/shape avatars are outside this measurement.

The skin patch contains the 28 vertices in the existing verified contact payload within 40 mm of the rest mesh's minimum Y. Its real skin weights and inverse bind transforms are used. Procedural patches come from actual boot mesh positions for near/mid, or the integrated lower-leg mesh for far. Far does not have the same articulated boot, so its results are reported separately, not treated as an equivalent rig.

For each fixed material vertex, only consecutive pairs with both endpoint clearances within ±10, ±20 or ±40 mm of the turf enter a contact episode. These are disclosed geometric sampling bands, not physiology or friction limits. Each episode reports duration, paired intervals, minimum/maximum clearance, foot/root cumulative and net X/Z displacement, and their ratio where root movement is nonzero. The same vertex is retained through an episode; no per-frame lowest-vertex switching occurs.

Speed, root pose, facing, movement heading, turn cue, ball-action influence and authored-retarget influence are exported. A `sourceRunEligible` flag requires speed ≥2.25 m/s, |turn cue| ≤38°/s, no ball action and zero retarget influence. It describes the current animation selection, not an assertion that the whole window is perfectly straight.

A second test checks exact repeated/reverse-seek contact positions and phase, plus near/mid boot parity. Finiteness and geometry identity are assertions; there is no pass/fail foot-sliding threshold.

## Native receipt

Both diagnostics pass in `/private/tmp/replayxi-parallel85-87-mixed-01.xcresult`, 2 cases, 0 failures. The export case took 0.952 s and the repeat/LOD case 0.399 s in that simulator run; these are test durations, not device performance measurements. The mixed bundle also contains unrelated UI pre-fix failures and is not a clean full-suite receipt.

Native attachment: `/private/tmp/replayxi-contact86-native-01/90D34AF5-A407-4FA3-BF22-779E6B532AA9.json`. It contains all 388 measured rows and 3,709 same-vertex band episodes. Analysis below uses those actual native world positions, not recreated rig math.

All 291 moving samples meet the recorded source-run eligibility policy. Ball-action and authored-retarget influence are zero. Actual path and body facing are not identical:

| Window | Speed range (m/s) | Path minus body heading | Root travel (m) |
| --- | ---: | ---: | ---: |
| Overlap jog | 3.177974–4.247305 | 7.203–9.086° | 3.153574 |
| Overlap run | 5.155551–5.533049 | 8.504–16.535° | 4.349433 |
| Recovery run | 4.566891–4.751005 | 3.952–11.479° | 3.759021 |
| Standing | 0 | Not defined | 0 |

These are nominal straight run segments, not perfectly constant-speed, facing-aligned motion. The gait clock uses raw segment-average speed while the displayed root follows the smooth presentation curve.

## Same-vertex near-floor travel

The longest observed skin episode per side in the ±10 mm band is below. These are observed durations within the chosen windows, not a reconstructed complete stance period; a window boundary can truncate an episode. Distances are cumulative X/Z travel.

| Window / side | Fixed vertex | Time (s) | Duration (s) | Foot (mm) | Root (mm) | Ratio |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Overlap jog / left | Body:2987 | 6.8500–6.9583 | 0.1083 | 71.226 | 460.651 | 15.46% |
| Overlap jog / right | Body:2448 | 7.2000–7.3167 | 0.1167 | 68.981 | 471.651 | 14.63% |
| Overlap run / left | Body:2987 | 11.9333–12.0333 | 0.1000 | 168.453 | 553.426 | 30.44% |
| Overlap run / right | Body:2481 | 11.6333–11.7417 | 0.1083 | 177.429 | 573.981 | 30.91% |
| Recovery run / left | Body:2980 | 13.6250–13.7167 | 0.0917 | 89.884 | 428.038 | 21.00% |
| Recovery run / right | Body:2481 | 14.0250–14.1333 | 0.1083 | 94.896 | 512.973 | 18.50% |

The wider ±20/±40 mm bands lengthen contact episodes and include more heel/toe rolling. Their complete per-vertex results remain in the attachment. They are not interchangeable with a physically measured planted-foot interval.

For the overlap-run left episode, net foot movement is 167.763 mm: 118.520 mm along body forward and 118.733 mm sideways, projected using the average endpoint facing. The root moves 537.630 mm forward and 131.272 mm sideways. The right episode is dominated by sideways foot movement (167.431 mm sideways versus 56.454 mm forward). Therefore a cadence-only change would not address all observed motion.

Standing skin vertices move about 4.89 mm cumulatively over 0.8 s (4.72 mm net), with the root fixed. This is source-idle motion, not seek drift. Procedural standing points are exactly fixed. Exact reverse/repeated-seek tests pass for every renderer, and near/mid boot geometry and world poses match exactly.

## More concrete LOD floor finding

The far mesh is one rigid whole-leg shape parented under each hip. It does not follow the knee/ankle joints used by the shared grounding calculation. `PitchSceneFactory` uses this same far rig as its regular table marker and applies the same authored pose.

Minimum measured point heights, including each player's real appearance scale:

| Window | Skin | Near/mid boot | Far integrated leg |
| --- | ---: | ---: | ---: |
| Overlap jog | +5.790 mm | −10.204 mm | −74.593 mm |
| Overlap run | +5.790 mm | −8.655 mm | −89.639 mm |
| Recovery run | +6.210 mm | −11.023 mm | −95.980 mm |
| Standing | +6.210 mm | +5.095 mm | +4.574 mm |

Worst exact far sample: red-lw at 14.083333 s, left mesh vertex `left:37`, world position `[29.14717865, -0.09597963, 21.09092522]` m. Unlike a horizontal near-floor motion inference, this is a direct below-turf geometry result. The licensed skin remains above the floor in every measured sample. Near/mid have a smaller independent clearance issue; those rigs are not treated as equivalent to the far mesh.

## Proposed next step and limits

Do not tune cadence from these ratios alone. First reproduce the far-mesh clearance in an actual scene regression, then consider a cached far-geometry vertical-only support guard. That would target a concrete geometry mismatch while preserving source skin, near/mid poses, trajectories and flight. It is only a proposal; no production fix is included here.

No Blender jobs or asset writes were needed for this measurement. Native point sampling does not establish how noticeable the horizontal motion is on Vision Pro, prove physically invalid contact, recover mocap, or measure hardware frame rate. Diagnostic source parses and passes the scoped diff check. Only the new test and this evidence document changed.
