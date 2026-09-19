# Run 149 — native cleanup provenance and off-ball support

Status: diagnostic checkpoint; unresolved cleanup crash and cross-runtime test issues continue in run 150. No production animation or physics change.

Run 148 shipped the optional local Full squad detail setting in `dd04e95`, with focused checks and Release build passing, but retained two full-suite RealityKit cleanup crashes. Six-method mixed cohorts, three repeats each, passed on both installed runtimes (26.5 and 27). That does not distinguish the cause.

## First-warning diagnostic

- Same prebuilt 148 binary, same six-method cohort, ten repeats. Result/log: `/private/tmp/replayxi-cycle149-weak-provenance.{xcresult,log}`.
- Root verified exact PID 77496 and its executable under the selected visionOS 27 simulator's app container before attaching LLDB. `objc_weak_error` resolved to one libobjc breakpoint.
- Capture the first breakpoint/stop with all-thread backtraces and registers, then detach/resume. No memory edits, security changes or guessed object addresses. Log: `/private/tmp/replayxi-cycle149-first-weak-lldb.log`.
- LLDB reports reading libobjc from process memory rather than the host shared cache. Debugger runs are not timing benchmarks. Any absence of app frames during queued teardown must remain an unresolved provenance limit.
- Production primary/aim worlds already detach while owned. Successful capture helpers await GPU completion. Inconsistent older test cleanup exists, but neither that nor the capture currently starting explains both warnings. Do not label a renderer's origin from the later crash stack.
- Outcome: **60 invocations passed**, 255.8 s test time. No weak warning, breakpoint hit or process restart. The test app exited normally; LLDB's queued backtrace command then reported that there was no stopped process and returned exit 1. This is a negative reproduction, not a crash stack or a fix.
- Independent unsafe-memory review found no demonstrable buffer-capacity, stride or escaped-pointer bug in the exercised paths. BGRA and float texture buffers match their formats; skin/contact arrays validate their counts. Native import/ownership defects remain possible.

## Independent motion diagnostic

An agent is preparing a test-only off-ball foot-support probe for rebound Argentina 13/19 and an away-team control. Use fixed native boot surface points, independently derived source support phases, actual near/low scene admission and exact reverse sampling. Low foot height alone is not proof of a planted foot; toe flex and legitimate swing motion are not automatically sliding. No rig correction is approved from unverified numbers.

- First candidate failed only its exact cross-POV boot-point check for France 26. Joint poses and replay data were exact. Receipt centroid differences peaked at 8.01 micrometres. The diagnostic used a relative-space conversion despite intending to avoid world-origin cancellation.
- Corrected measurement composes the verified local transform chain (bounded to 16 entities, requiring the actual skin root and actor). It preserves strict exact checks for local transforms, boot points and rewind; no tolerance was widened.
- `/private/tmp/replayxi-cycle149-support-candidate-02.xcresult`: **passed**, 5.992 s. Six cases × 67 frames = 402 native pose samples, plus reverse playback. The old relative API differs from local-chain points by at most 7.63 micrometres across cases. The corrected France 26 control is exactly identical across POV origins.
- Accepted receipt: `/private/tmp/replayxi-cycle149-support-02-captures/E05C64BF-174D-4B18-A745-ABF23C5B22E5.json`.
- Argentina 13's right source-support episode is 0.4667–0.6167 s; Argentina 19's left is 0.5000–0.6500 s. Source-run weight is 1. Fixed vertices remaining within 10 mm of the pitch travel up to 119/101 mm (13 near/low) and 194/194 mm (19 near/low). Near/low vertex sets differ, so their maxima are not a matched-vertex comparison. These are geometric motion measurements, not force-plate contacts or proof of visible sliding.
- France 26 has a partial source blend (minimum run weight 0.809), with the measured patch above 44 mm; it is not a planted-foot control in this window.
- Source-stage backward motion precedes retargeting; retargeting reduces it and floor correction leaves horizontal positions unchanged. Current cadence is not calibrated to the imported in-place run's stride. Exact original root-motion calibration and native moving views remain required before a correction.
- Epic's [pose-warping documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/pose-warping-in-unreal-engine) describes speed-ratio stride scaling with leg/pelvis adjustments. That is a reference for a possible bounded native IK approach, not code already implemented here.
- Full suite on installed visionOS 26.5: `/private/tmp/replayxi-cycle149-full-runtime265.xcresult`, **1,489 passed, five failed, two skipped**, 355.2 s. No unknown-weak warning, native crash or process restart. This single run does not prove the intermittent issue is exclusive to visionOS 27.
- All five failures assert Swift texture-wrapper identity: one kit-map test, one far-head test and three palette tests. Kit getters produced 44 object identities while loading only six maps; generation/load counters and pixel checks passed. Public `TextureResource` equality and shared replacement/readback behavior will be tested with fresh textures before revising those assertions. No private GPU handle or name-based shortcut is planned.
- Diagnostic code backed up as `6078f41` and pushed. Exact original source-stride calibration and fixed-camera native sequences continue in run 150; neither is yet a rig correction.
- Calibration note: a previous research message's 300–400 cm figure was the non-shipping pilot builder's acceptance range, not a measured shipping stride. The committed animation has already had root X/Z removed. The original pinned run FBX must be retrieved and measured before using any distance value.
