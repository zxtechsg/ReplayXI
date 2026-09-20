# Run 158 — bounded arm-transition experiment

Status: simulator validation complete; physical-headset gate pending. The arm experiment is numerically verified, not a claim of headset-level realism.

## Previous checkpoint

Run157 is committed and pushed as `86b7fae561325b1a1f1008615b3de97062a80544`. Final normal-Debug integration passed 47 tests; optimized candidate passed 38; unsigned device Release passed. The latest Debug launched on the main visionOS27 simulator, PID2364. Static capture: `/private/tmp/replayxi-cycle157-launched.png`; review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`. No interactive headset claim.

## Scope and acceptance

157 identified steep but continuous arm admission, not a quaternion flip. Experiment with an absolute-time, cold-prepared lower envelope for only the non-contact cut contribution to arm influence. Preserve source time, body/leg/chest weights, phase, contact/readiness overrides and supplied-locomotion authority. A live minimum must prevent new cut activation, but its slope is not mathematically bounded by the envelope alone.

Reuse the immutable native-recording root lifetime; no new global or per-skin cache. Bound storage, report cold preparation separately, and measure warm provider/scene CPU without renderer or FPS claims. Test stale track/source/time admission, reverse seeking, both teams and all five real demo tracks. Check final root and legs explicitly: the floor guard also sees arm-influenced vertices.

Capture matched actual near/low native rigs before claiming visible improvement. Fixed camera and timestamped frames must preserve player travel. Existing149's intermittent renderer cleanup crash remains unresolved; isolated render checks are not evidence that it is fixed.

Root owns builds, receipts, integration, Git and this log. Three agents own independent timeline/provider, factory/performance, and native visual-test files. User project/signing edits remain untouched.

## Interim checks

The independent dashboard/accessibility and local review workflow checkpoint was committed and pushed as `1920a9d`. Its combined POV → keyframed arc → scrub → save → relaunch → restore test passed on visionOS26.5. Match-study disclosure and cue VoiceOver labels were clarified. The original user project/signing changes remain unstaged.

The first normal-Debug run of the arm candidate passed four numeric tests. It covered ARG10 rebound and the strongest filtered-cut window from each team in all five demos, both rig details, exact protected contacts, source/non-arm/root/phase equality and reverse seeks. At the ARG10 rebound window, the largest local arm step fell from 25.770° to 8.793° per 120 Hz interval; six-joint arm path was 875.4° versus 1000.5° in the old control, and upper-arm excursions remained 117.4°/102.1° versus 125.8°/104.4°. These are skeleton measures, not perceived quality.

The first three cache tests failed because their fixture sampled 7.1–7.6 s in a seven-second clip. Corrected tests use the active 1.6–2.25 s window and require actual positive suppression. All three then passed. One normal-Debug native rebound root prepared 20 arm tables in 144.6 ms, with 67,280 bytes of Float weights and 33,141 evaluated raw samples. The cold time includes instrumentation, not device load. Near/low warm provider batch medians were 8.29→8.26 ms and 18.53→19.15 ms per 40 updates in one alternating A/B, too little evidence for an FPS or uniform speed claim.

Original 50-frame moving native captures passed separately for near/low × baseline/candidate, with source, legs, player and ball trajectory, contact-aware old oracle and exact rewind checks. The fixed close-view add-on passed for both details, two source frames per detail, with original and candidate captured at the same fixed camera. Visual inspection shows a small arm-pose change and no obvious change to player travel; the stills cannot prove motion quality in a headset. The known149 renderer cleanup path was simplified by removing only its transient child-array detach. One isolated 136-frame capture and the ordered 145→147→149 sequence passed on visionOS26.5. Full visionOS27 regression is pending; this does not establish the underlying RealityKit crash's root cause.

Matched optimized scene update diagnostics passed all five demos for both the old157 and candidate158 builds on the same visionOS26.5 simulator. Across 963 timed forward updates, mean CPU time changed from 0.3335 to 0.3466 ms/update and the empirical p95 from 0.3631 to 0.3818 ms/update. This is a roughly 3.9% mean cost in one run, not renderer time, paced FPS or headset performance. Normal-Debug cold preparation of one 20-player root took 144.6 ms and stored 67,280 bytes of weight tables. The candidate's added CPU cost is a tradeoff for bounded arm transitions; hardware validation remains required.

No physical Vision Pro is connected; Xcode lists known headsets as unavailable. Simulator checks can establish implementation behavior but not actual hand comfort or headset FPS. A headset connection was requested for that final gate.

## Final checks

Full normal-Debug regression on visionOS27: `/private/tmp/replayxi-cycle158-full27.xcresult`, **1,622 passed, 0 failed, 2 skipped**. The formerly crashing 149 render test passed inside the full run. The earlier isolated and ordered 26.5 runs also passed. An intermittent RealityKit teardown crash cannot be ruled out by these runs; the removed child-detach loop is the narrowest supported cleanup change.

The final unsigned visionOS device Release build succeeded (`/private/tmp/replayxi-cycle158-release-final.log`). The only build warning was expected skipped App Intents metadata extraction; the arm timeline's actor-isolation warning was fixed. The main visionOS27 simulator runs the new Debug app normally, PID 8521. Static capture: `/private/tmp/replayxi-cycle158-launched.png`. The *current* app container's review file SHA-256 was `8011f44456f802b17631b01fe886b14bb609d3ecb14521a5a22b45ae28d0d39e` both before and after this launch. It has an autosaved review and zero named saved reviews. This differs from the historical SHA above; the file modification time is 10:57, before this run's full tests. The reason for that earlier change was not established here, so do not claim continuity with the old hash.

No new global head, turn, or foot-contact rigging change was justified by the available evidence. Existing native bounds cover the five demos: head yaw ≤70°, pitch ≤40°, per-frame turn ≤12°. Source-derived sole displacement during one rebound phase is not a measured planted-foot defect; fixed-camera images show a running stride. The remaining high-fidelity/realism request needs authoritative multi-angle tracking or mocap plus on-device visual review, not a guessed procedural pose.
