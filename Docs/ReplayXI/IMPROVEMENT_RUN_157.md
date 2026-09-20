# Run 157 — review clarity, label cost, motion attribution

Status: verified. Corrected baseline 26 tests passed; optimized candidate 38 passed; final normal-Debug native integration 47 passed. Unsigned device Release passed. No production motion change.

## Previous checkpoint

Run156 is committed and pushed as `2bbda745a3229eef8fdace2d8072cee22e1ca23d`. Full regression passed 1,598 tests with two intentional skips; 41 final focused tests and unsigned device Release passed after the last feedback-lifetime correction. See run156 for exact chronology and the corrected native fixture.

Final156 launched normally on the main visionOS27 simulator, PID99114. Static launch capture: `/private/tmp/replayxi-cycle156-launched.png`. User reviews retained the same SHA-256 before/after install: `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`. New data container: `853BC18A-B105-4656-9A2B-C3D1F6EEB738`. No headset/hand input claim. The earlier intermittent full152 cleanup crash remains unresolved.

## Bounded scope

- Show the exact saved-review target in Load/Delete confirmation. Preserve captured restore and live UUID deletion semantics, cancel behavior, scroll limits and large-text access.
- First measure current identical player-label collision-box generation requests with DEBUG-only timing/counts. Only then test a shared fixed shape. Preserve actual collision bounds, picking, hover, visibility and scene graph. Operation counts are not GPU allocation or FPS measurements.
- Diagnose the latest native rebound Argentina #10 forearm peak near 1.825 s. Compare local and global motion through source, retarget, off-ball/look and final stages in both detail levels. Shrinking time steps must distinguish a discontinuity from steep continuous motion before changing production rigging.

Root owns builds, receipts, integration, Git and this document. Agents own separate UI, label instrumentation and motion-diagnostic files. Preserve unrelated user project/signing changes.

## Baseline and UI checks

The initial optimized baseline build (`cycle157-label-baseline26.xcresult`) failed before tests: the new native screenshot helper needed explicit `self` inside a lazy `compactMap` closure. Corrected that test-only error. Also moved two older test helpers' actor-isolated default values into their method bodies; no production semantics changed. Existing UIKit test-window deprecation warnings remain.

Corrected optimized Debug baseline on visionOS26.5: `/private/tmp/replayxi-cycle157-label-baseline-fixed26.xcresult`, **26 passed, zero failed**. The unfinished, test-only arm diagnostic was explicitly excluded from this build by filename; all measured production files were frozen.

Receipt: `/private/tmp/replayxi-cycle157-baseline-captures/4F84DD12-B748-4387-869C-BC0894287B3A.json`. Five real rosters, four new label roots each: 440 public box-generation requests, exactly 22 per root. Nested generation time was 0.819–1.497 ms/root, 1.11–4.23% of measured label construction. Ordinary repeated roots were about 30–33 ms; the first observed root was 130.427 ms. This narrower label-only timing is not directly interchangeable with earlier whole-root labels/selection stage timing. No rendering, private-allocation or FPS claim.

Saved-review confirmations now show the full selected name and wrapping `scenario · 00:00.00`. Review rows use the same bounded hundredths formatter. Tests preserve live-UUID deletion, captured named/Last-session restores and Cancel with unchanged disk bytes. Native default/AX5 long-name target and action captures were checked; both actions fit, so their top/bottom captures are identical. No clipping or actual scroll-motion/headset claim.

Candidate: share one immutable player-tag ShapeResource, retaining independent entity transforms/collision components and exact bounds. DEBUG counters time only the one initializer; resetting observations does not evict its resource. The arm diagnostic now narrows the final-stage peak without assuming retargeting caused it. Candidate tests and device Release are in progress.

## Candidate evidence

Optimized candidate `/private/tmp/replayxi-cycle157-candidate26.xcresult`: **38 passed, zero failed**; unsigned device Release `cycle157-release.log` passed. Candidate label receipt: `6244E605-FAE1-4D75-9B83-BAFB234DCD1D.json` under `/private/tmp/replayxi-cycle157-candidate-captures`.

All five first-scene graphs compare exactly to baseline: transforms/visibility, model and collision bounds, static/mode/filter, input, hover and accessibility. All 20 per-root counts and text-cache observations match. Each root has 133 entities, 110 models/materials and 22 colliders/input/hover targets. Public shape generation falls **440 → 1**; the one observed initialization takes 0.396 ms, with zero generation on the following 19 roots.

Repeated-within-scenario roots (15 samples): median label time 30.897 → 30.246 ms; paired median delta −0.640 ms, 13 faster and two slower. First observed root was 130.427 → 130.661 ms; City45's first root was slower too. This single A/B supports removed calls and a small observed repeated-root saving, not a uniform or proven repeatable speedup, whole-scene gain, private allocation reduction or FPS claim.

## Arm attribution (no production motion change)

`32F5ABBF-9F4E-4EC4-8A45-FD1860A67C0D.json` records both LODs. At 1.816667 → 1.825 s, ARG10's left forearm rotates 1.77° in the source, 25.19° after retargeting, and 25.77° at final output. Cut/arm influence rises 0.694 → 0.925 over 8.33 ms; phase admission stays one and no contact is active. The source/target quaternion dot remains positive around 0.795 → 0.759, far from the 180° boundary.

Shrinking intervals near 1.819954793 s reduce the final elbow difference from 26.207° at 8.33 ms to 0.6763° at 0.2 ms, 0.06733° at 20 µs and 0.00774° at 2 µs. This identifies steep continuous admission, not a quaternion flip. Intermediate global matrices are rebuilt on captured copies; partial retarget reconstruction must match native locals exactly before full-target comparisons are accepted. Six protected contact samples per LOD remain exact, with rewind, bone lengths, floor and recorded contacts preserved (`4D0F06EE-1319-4796-9E4C-B09BE103267A.json`). A moving visual comparison remains necessary before claiming perceptual improvement.

Next candidate: smooth only the non-contact cut contribution to arm influence, retaining body/legs/phase and contact overrides. Keep it deterministic under reverse seeks and measure actual native motion and CPU before acceptance. Current157 ships no motion change.

Final normal-Debug integration, including all-five native scene work, spatial hover, input restoration, exact text placement, saved-review behavior/layout and arm attribution: `/private/tmp/replayxi-cycle157-debug-integration26.xcresult`, **47 passed, zero failed**. This is a focused integration run, not a repeat of the 1,600-test run156 suite. Final production files match the passing unsigned Release build.
