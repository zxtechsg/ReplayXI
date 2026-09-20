# Run 152 — time-bounded jog admission

Status: targeted native, dense-policy and optimized checks passed; unsigned device Release build passed. Full regression is still running after one native cleanup crash/restart; not yet launched as the working demo.

## Reason

Run 151's raw speed/turn/yaw policy passes its scalar continuity tests, but actual authored turn signals can cross those ramps very quickly. Liverpool 38 produces a roughly 100 ms 0→1→0 pulse; the same-window maximum local joint step rises from 4.90° to 30.37° at 120 Hz. That peak is a finger, not a torso/leg measurement. Keep the raw receipts in run 151 rather than treating a passing diagnostic as visual acceptance.

## Candidate

- Build a per-track 120 Hz admission table on the scene's cold path. Exclude all recorded touch actors, keepers and authored impacts before construction. Explicit impact actors remain excluded for the entire supplied cue, including outside its active time window.
- Apply forward/backward lower-envelope passes, limiting weight change to 4 per second. Linear lookup at absolute replay time is independent of playback history, speed and seek direction. A complete 0↔1 change needs at least 250 ms.
- Sample cell midpoints too; known zero/invalid cells cap both endpoints to zero before the passes. Do not add a live raw clamp: it would restore the sharp exit. These bounds apply to the sampled table, not a formal proof about every unsampled track instant or the final joint pose.
- Bound preparation to the native recording contract: nonnegative absolute time, endpoint at most 1,000,000 s, positive span at most 90 s. Invalid/oversized inputs retain the original animation.
- Native roots own their immutable tables, avoiding player-ID-only global cache collisions across matches. Report cold build cost, sample count and retained scalar bytes separately from warm factory CPU cost.

## Required checks

1. Pure rate/minorant/zero-cell/rewind/offset-time tests; finite bounded inputs and memory.
2. Dense actual-track checks for unexpected positive weights at excluded raw/cut boundaries; do not hide misses with an instantaneous clamp.
3. Repeat all-five-demo protected-pose/ball/route/rewind checks and compare source-pair joint steps, including major limbs, at the previously offending instants.
4. Repeat the same native near/low capture windows. Attenuating a brief pulse is expected; do not require it to retain a full 0→1 swing.
5. Optimized CPU evidence, full regression and device Release build before a normal demo launch. Preserve user reviews and unrelated edits.

## Targeted results

- Six timeline tests passed in `/private/tmp/replayxi-cycle152-timeline.xcresult`. At 960 Hz across 82 eligible tracks: no positive weights at sampled hard exclusions or above 3 m/s, 244,070 positive samples, maximum measured slope 4.000025/s (Float rounding). All five banks retain 398,488 bytes of Float payload, excluding container overhead; 199,162 raw policy requests in total.
- Seven native tests passed in `/private/tmp/replayxi-cycle152-native.xcresult`: four arc-limit regressions, two actual-factory integration tests and the matched capture test. The integration run checks 650 paired samples over ten cases/all five demos, both teams and both detail levels. Protected poses, ball/routes, floor/bones, bounded weights and exact rewind pass. This is selective coverage, not proof for every continuous frame.
- Exact City57 LIV38 pair, 4.066667→4.075 s: the affected finger step falls from raw151's 30.374° to 1.436°; same-pair major-joint maximum falls from fast-only 3.910° to prepared 3.708°. Exact City45 LIV2 pair, 2.883333→2.891667 s: affected finger falls from raw151's 22.621° to 0.823°; major-joint maximum falls from fast-only 3.345° to 3.273°. The latter actor is only covered at low detail in this integration sample.
- In matched native windows, ARG19's maximum returns to the fast-only 7.556° toe step. LIV38's prepared maximum is 4.997° at the right calf versus 4.883° at the same fast-only frame (the independent fast maximum is 4.904° at another frame). A small CITY20 toe increase, 7.521→7.575°, remains in the integration sample. These are not evidence of EAFC-level animation.
- All 24 native 512 px PNGs were independently reviewed. No new target crop, obvious limb stretch or low-only defect was found. Existing diagnostic limits remain: black pitch/background, reversed labels, oversized selection marker, occasionally cropped non-target actors. Stills do not establish motion smoothness or headset comfort.
- Two optimized Debug integration tests passed in `/private/tmp/replayxi-cycle152-optimized.xcresult`, using `SWIFT_OPTIMIZATION_LEVEL=-O ENABLE_TESTABILITY=YES`. Warm factory-only median CPU: fast-only 0.466–0.523 ms; prepared 0.473–0.584 ms; paired median increase 0.007–0.061 ms. This is unpaced CPU, not GPU/frame-rate or device evidence.
- Optimized cold timeline preparation: 11.040–15.605 ms per root; 15–17 tables and 57,188–97,260 retained weight bytes. Whole-root construction: 78.946–300.494 ms after shared asset/physics prewarm. **Both comparison roots prepare the tables**, so these are measured costs, not a historical cold-start A/B claim.

## Evidence and limits

- Native integration receipt: `/private/tmp/replayxi-cycle152-native-captures/19C62183-4DAE-4E88-90DB-3327C652CEA6.json`.
- Native visual receipt/manifest: `/private/tmp/replayxi-cycle152-native-captures/DAA49CBE-A33E-4BD6-AE28-3D6E0B252674.json` and `manifest.json` (24 PNGs, 1,301,082 bytes).
- Optimized receipt: `/private/tmp/replayxi-cycle152-optimized-captures/44665670-6044-4615-93F7-1655F6382422.json`.
- Visual receipt `weightBefore/After` belongs to the named variant; `pairedWeightBefore/After` belongs to the other variant. Zero paired weight on a prepared peak is the fast-only control, not corrupted data.
- The table is a lower envelope at sampled knots/known zero cells only. At arbitrary nonzero-policy times it may exceed the raw cap slightly; no continuous lower-envelope or final joint-velocity guarantee is claimed. Brief pulses are intentionally attenuated.
- The earlier intermittent native cleanup crash is unresolved. Passing this run alone cannot establish a fix. No hands-on headset/gesture verification while the Mac is locked.

## Full-run investigation (in progress)

- `/private/tmp/replayxi-cycle152-full27.xcresult` is still running. PID 87990 crashed during `ReplayAthleteOffBallVisualTests.testActualReboundBootMotionFixedCameraNearLow149`; Xcode restarted the test host. This is a failure, not a clean regression result.
- Crash report: `/Users/zx/Library/Logs/DiagnosticReports/ReplayXI-2026-09-20-083948.ips`. The main-thread stack starts at `weak_clear_no_lock`, then destroys a CoreRE transform/entity and a Swift array inside `captureSupport149`. Unlike the earlier physics-world cleanup stack, this one identifies a visual-test ownership scope. Root cause remains unproven; no preceding unknown-weak warning was found.
- Device Release build: `/private/tmp/replayxi-cycle152-release.log`, successful. Only the unused AppIntents metadata extraction warning was reported. This does not exercise simulator cleanup or prove physical-device behavior.
