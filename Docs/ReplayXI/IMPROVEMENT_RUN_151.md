# Run 151 — bounded slow-run integration plan

Status: raw admission candidate rejected for sharp-turn transitions; temporal refinement pending. Arc-warning fix passed. Run 150's native A/B was promising for two gently accelerating outfield players, not a global contact or speed-transition validation.

## Scope

- First candidate: native-recording outfield players with no recorded touch or impact anywhere in that scenario. Keep contact actors, keepers, impacts, stationary practice and overridden motion exactly on the existing path. No new UI setting.
- Add an optional compact slow clip bound to the verified base-motion hash and pinned source. Approximately 180 KB JSON / 92 KB raw decoded TRS before overhead, shared once. Do not duplicate idle/rest/skeleton or change the existing base asset/hash/contact profiles.
- Cold prewarm validates the entire optional package before publication. Missing or invalid optional data must leave the existing skinned fast package working, not force a procedural fallback.
- Preserve absolute gait phase, actor routes, ball recordings, head/POV controls and deterministic reverse seeks. Blend the whole body, not legs alone.

## Transition hypothesis — not yet approved for shipping

- Quintic speed rise 1.0–1.9 m/s, full weight 1.9–2.2, fall 2.2–2.9. Turn-rate fade 20–38°/s. Slow is zero before the existing fast-specific cut phase above 3 m/s.
- Permit three clip interpolations only where idle, fast and slow all contribute; otherwise one or two. One reusable output pose, no additional hierarchy passes or per-frame decode.
- A strict two-clip limit would force a narrow onset near the existing full-run threshold (~1.95 m/s). Reject that shortcut: same-phase knee differences reach 49.9°. A 0.087 m/s fade crossed at 2 m/s² lasts ~43 ms; the broader ramps last 350–450 ms. These accelerations are illustrative, not measured match data.
- Current A/B covers only about +0.046 to +0.125 m/s² and no complete onset/exit. Directional suitability and real rise/fall/turn boundaries still need evidence. The gates above are hypotheses to test, not proof of smoothness.

## Required evidence

1. Decoder/hash/layout failures, optional-load fallback and atomic publication.
2. Exact old poses and no added slow sampling for excluded actors and zero-weight endpoints.
3. All five actual demos, both teams and LODs: gate entry/exit, deceleration, turns, exact rewind and unchanged ball/contact data.
4. Native moving comparisons; bone/floor bounds and normalized per-joint step measurements. Do not convert low boot height into an asserted ground contact.
5. Measured clip-sample counts and factory CPU cost; no simulator result presented as headset FPS.

Reference evidence and known limits: `IMPROVEMENT_RUN_150.md`. The intermittent native cleanup crash remains separate and unresolved until directly evidenced.

## Candidate implementation

- Optional `ReplayXIRocketboxSlowRun.json`: 181,348 bytes, SHA-256 `865b7d45ce021731adb8b80febb89c39d5f71a42f284af10be3a601cad33890e`. Contains the intact, unshifted 24-frame slow clip, source/base identities and full MIT notice. No duplicate skeleton, idle or contact geometry.
- Root independently reproduced it with `Scripts/build_replayxi_slow_run_asset.py` into `/private/tmp/replayxi-slow-asset-root151.AEi3o3/slow-run.json`; byte count and SHA match. The original pinned FBX and previous independent fixture are checked before packaging.
- Provider validates the optional package on cold prewarm. Missing, corrupt, oversized or changed data leaves the existing base rig usable. Existing contact profiles remain bound to the unchanged base motion hash.
- Native factory admission excludes every recorded touch actor and the authored/explicit impact actors for their entire tracks. The instance also rejects stationary poses, keepers, action cues and callers that do not opt into exact track sampling.
- Direction uses the already-computed travel-versus-facing yaw: full through 0.22 rad, quintic fade to zero at 0.72 rad. No directional inference from scalar speed. A missing movement sample stays on the original source.
- The original source path remains exact at zero weight. Whole-body blending uses one pose buffer, at most three contributing clips and no extra hierarchy rebuild. DEBUG-only counters report actual clip samples.
- Frozen run-149/150 diagnostic helpers explicitly disable the new source, preserving their historical fast baseline. New run-151 tests exercise default factory admission; old anchors are not silently regenerated.

## Initial validation

- `/private/tmp/replayxi-cycle151-source.xcresult`: 39 passed, zero failures. Includes the eight speed/turn/direction admission tests, ten supplemental decoder/sampler/fallback tests and 21 existing motion/runtime tests. All Swift was frozen during compilation and execution. Supplemental resource is present in the built app.
- `/private/tmp/replayxi-cycle151-fast-controls.xcresult`: three historical native-control tests passed using that same compiled binary (`test-without-building`). Exact frozen support data and fast/slow A/B remain valid. Unrelated new test/UI source could be edited during this run; none was compiled or read by these tests. Simulator shader-pipeline warnings occurred; a passing test is not a claim of warning-free graphics.
- The normal app's saved review file still has SHA-256 `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65` before these runs. Full-demo blend/CPU validation and a fresh device build remain pending at this checkpoint.

## Tracked arc warning

- Reproduced a stale pitch-limit warning in the actual rebound study: create an arc from (−30, 0) to (−30, 4) at 0 s, follow Argentina 24, then seek to 7 s. Its displayed endpoints move to (−33, 15.5)/(−33, 19.5); the curve control crosses the touchline, but the old warning still checked its original endpoints. The reverse case also left a stale warning after moving away.
- The pad now resolves the same view-specific tracked/keyed endpoints as rendering, sampling only its attached players (at most two). Saved marks, curve values and rendering itself are unchanged.
- `/private/tmp/replayxi-cycle151-arc.xcresult`: 39 passed, zero failures, including four new regressions for entering/leaving the limit, ideal stations versus telemetry, rewind and keyed elevations. An unrelated integration-test file was published as the freeze request arrived and was not included in this build; the next frozen integration build will compile it and repeat the arc checks.
- Core source checkpoint `b876f11` is verified on the remote. User project/signing changes remain excluded.

## Full-demo evidence and rejected transition

- `/private/tmp/replayxi-cycle151-integration.xcresult`: six tests passed (four repeated arc regressions plus two native integration tests), with all Swift frozen. Ten team-focused cases cover all five demos; both teams and both skin detail levels actually receive positive weights. Protected actors, ball/actor transforms, sample counts, bone/floor bounds and exact rewind pass. Receipt: `/private/tmp/replayxi-cycle151-integration-captures/77B89EED-6B72-4955-8CC1-F745233CA9A5.json`.
- A passing diagnostic does **not** approve the motion. Liverpool 38's raw turn metric opens a roughly 100 ms source pulse in the underlap study. At 4.0667→4.075 s, weight drops 0.9828→0.3886 (−71.30/s). Liverpool 2 also changes +56.04/s near 2.8917 s in the overlap study. Broad scalar thresholds alone do not bound changes over time.
- Unpaced Debug full-squad factory median CPU is roughly 11.30–12.38 ms fast-only and 11.67–13.29 ms enabled across the ten cases; this is not optimized device performance or FPS. Dense source interpolation adds measurable cost; future cold table preparation must be measured separately.
- `/private/tmp/replayxi-cycle151-visual.xcresult`: the native capture test passed, preserving actual actors, ball, cameras, joints through renders and reverse seeks. 24 original 512 px PNGs, 1,300,660 bytes. Receipt: `/private/tmp/replayxi-cycle151-visual-captures/94F8B910-6043-4B89-A2B7-8BC08F6C7D06.json`. Root inspected four near-detail midpoint images.
- Same-player, same-window maximum local joint step at 120 Hz: Argentina 19, volley 8.15–8.35 s, fast 7.56° versus candidate 16.30°; Liverpool 38, underlap 3.975–4.175 s, fast 4.90° versus candidate 30.37°. Candidate maxima are finger joints, **not** a measured 30° leg or torso jump. Still images alone cannot establish smoothness; the measured source pulse is rejected despite the tests passing.
- Next: an absolute-time, cold-built, rate-limited admission envelope. No previous-frame smoother, route/ball change or live raw clamp. Preserve this raw-candidate evidence and compare the refined source at these same windows. No final device build or normal demo launch has been claimed for this candidate.
