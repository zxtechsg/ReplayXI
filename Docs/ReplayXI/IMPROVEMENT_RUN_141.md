# Improvement run 141

Local-only Match Replay and Strategy Analysis. Goal remains active. Personal
signing and Info.plist edits are excluded from Git backups.

## Header hand-off: measured baseline

The final-81-volley-v2 France #10 header has a discrete chest-retarget switch
at both ends of its action sample. Native stage traces locate the jump in
football retargeting, before header aim or final floor correction. The source
animation's chest steps stay below 0.56 degrees in the measured windows.

At global 120 Hz, entry peaks at 28.619 degrees and exit at 30.743 degrees.
Shrinking the samples to 10 microseconds either side still yields approximately
28.620 and 30.865 degrees: these are discontinuities, not just fast movement.
Near and low-detail skins reproduce the issue. The proposed correction changes
only the chest hand-off around a validated header cue, not the match routes,
clock, ball physics, source animation or actual contact pose.

Three baseline tests pass. Pre-fix receipts freeze 87 meaningful positive-action
poses and 15 full-support poses per detail, source poses and the native ball
trajectory. Zero-influence endpoints are diagnosed separately; their defective
old poses are not treated as a preservation target.

- `/private/tmp/replayxi-cycle141-header-baseline.xcresult`
- `/private/tmp/replayxi-cycle141-header-baseline-captures`

### Correction and validation

Header-only chest admission now eases over the existing 120 ms preparation and
release margins. The same partially admitted chest feeds arm targets. At full
protection the old source-chest branch is retained exactly. Other actions and
callers without a header cue keep their prior path. A DEBUG-only bypass exposes
the measured old behaviour for comparison; no new joint-angle clamp is used.

Both detail levels produce the same measured changes:

| Window | Chest peak before / after | All-joint peak before / after |
| --- | --- | --- |
| Header entry | 28.619° / 3.758° | 28.619° / 6.357° |
| Header exit | 30.743° / 3.630° | 30.743° / 5.459° |

These are steps on the same global 120 Hz grid over ±160 ms windows. At ±10 µs,
chest differences fall to 0° / 0.040°. Every frozen meaningful-action,
full-support and source-pose hash passes. All 1,261 native ball positions match
the baseline hash; the recording retains five touches. Exact reverse seeking,
bone lengths, floor clearance and unchanged non-header/default overrides pass.

All 16 calibrated native near/low matched images were inspected. The abrupt
upright/leaning change disappears between the boundary frames; no new visible
mesh break was found. These are still images, not headset comfort or FIFA-level
animation evidence. Existing tests also retain real head-surface contact for
both the France and City headers across all three detail levels.

## Select moving annotations at the current time

Spatial tap, recovered short tap and accessibility activation now pause on the
pose the coach selected. Previously they all called the review-from-In action,
rewinding an animated annotation before the next edit. Only coach-created
keyed/player-following annotations use the new selection path. Static authored
overlays and explicit event review keep their established reveal-time jumps.
The selection resolves the current saved mark, not stale callback data, and
respects active edit ownership.

Nine native regressions cover actual arc segments/cards/handles, forward and
reverse selection, editing an existing key or adding an interpolated key,
autosave, erase and one-step Undo, deleted targets, In-inclusive/Out-exclusive
visibility, selected out-of-window previews, tracking and input guards.

The combined 40-test candidate cohort passes with no failures:
`/private/tmp/replayxi-cycle141-candidates.xcresult` and `.log`.
Header PNGs and quantitative receipts:
`/private/tmp/replayxi-cycle141-header-candidate-captures`.

## Floor attribution: no shipping optimisation

Three test-only native checks pass with `SWIFT_OPTIMIZATION_LEVEL=-O`,
`ENABLE_TESTABILITY=YES` and DEBUG retained. Eight alternating-order pairs of
128 requests compare floor-only scans with whole skin updates. Captures,
oracles, assertions and preparation are outside timed sections; observers are
removed before warmup. Both paused and forward/reverse inputs are covered.

Per-request medians, in microseconds:

| Group | Floor, paused / moving | Whole update, paused / moving |
| --- | --- | --- |
| One near skin | 0.729 / 0.683 | 8.826 / 10.813 |
| One low skin | 2.650 / 2.512 | 9.046 / 10.729 |
| One near + three low | 7.999 / 8.097 | 35.436 / 39.445 |

The mixed floor scan takes about 20–23% of isolated skin-update time, but only
eight microseconds in this test. Its full coverage remains unchanged. This is
optimised simulator CPU attribution, not Release, active-renderer, complete
scene, device or FPS evidence. The authored inputs use inferred action cues,
not native-ball bake outputs. All admitted probe minima match an independent
JSON oracle exactly; every imported low-mesh vertex is checked separately to
10 micrometres, including affine variants. Malformed poses fail safely.

- `/private/tmp/replayxi-cycle141-floor-optimized.xcresult` and `.log`
- `/private/tmp/replayxi-cycle141-floor-optimized-captures/B4C1BCE2-6BCA-46AB-A515-AF5675BF28A5.json`

## In progress

- Refresh full-scene CPU measurements for all five native reference studies.
- Run the complete native regression suite and unsigned device Release build.

The Mac remains locked. Offscreen native tests are available; hands-on headset
gesture, gaze and comfort testing is not claimed.
