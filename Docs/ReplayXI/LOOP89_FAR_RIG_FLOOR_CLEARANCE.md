# Loop 89 — Actual-scene far-rig floor clearance

## Confirmed scope

The rigid far leg can cross the pitch while its shared authored pose is grounded as an articulated near leg. This is separate from the horizontal foot-travel measurements in Loop 86. No cadence, trajectory, skin, asset or camera change is proposed.

Actual hierarchy:

`player (focus scale/yaw) → table-marker (appearance scale) → body-root → hips → hip → rigid whole-leg mesh`

The knee and ankle entities animate, but the far mesh is not their child. The shared authored vertical solver assumes the bent 0.39 m + 0.35 m leg chain and a separate boot. That support calculation does not describe the far silhouette.

## Pre-fix scene evidence

`ReplayFarAthleteGroundingTests` runs the real `makeMatchRoot` and `update` pipeline. It selects the goalkeeper so the measured runners remain visible far markers. Mesh vertices are converted to match-root coordinates, preserving focus scale, appearance and the current hierarchy. Measuring relative to the pitch avoids mistaking a tilted miniature table's room Y for clearance.

First receipt: `/private/tmp/replayxi-parallel88-91-repro-01.xcresult`.

- The scene-floor case fails all 18 assertions: 3 exact poses × 3 views × skin prewarm off/on.
- The clear-flight/added-height, near/mid exact-pose and reverse/view-repeat controls pass.
- The action case initially throws a test-harness error: rebuilding a binding after the factory renamed its root from `full-rig` to `table-marker` violates that binding's parent-name check. This is not a product defect. The harness was corrected to inspect live joint entities directly, without re-binding or modifying the graph. No floor threshold, fixture or articulation assertion changed.

Corrected receipt: `/private/tmp/replayxi-parallel88-91-mixed-02.xcresult`. Both floor cases fail, with 21 assertions: 18 scene plus 3 action. The other 3 cases pass; all authored-articulation controls pass. At the active `navy-rb` touch at 17.5 s, the far mesh is below the pitch by 16.465 mm in Table, 11.244 mm in Touchline and 8.031 mm in Player POV (pitch-local units). The two `navy-rw` touch fixtures already clear the floor. Action attachment: `/private/tmp/replayxi-far89-actions-before-02/121D5992-8FA7-47C7-94AC-DB5DB3B0125B.json`.

Scene attachment: `/private/tmp/replayxi-far89-scene-before-01/066D1947-5A09-46F4-AC5D-8B52DD8DDCF5.json`. All 18 measured markers are enabled. Skin prewarm does not change their geometry results.

| Player / time | Table minimum | Touchline minimum | Player POV minimum |
| --- | ---: | ---: | ---: |
| navy-rb / 6.950000 s | −152.918 mm | −104.431 mm | −74.593 mm |
| navy-rb / 11.691667 s | −183.760 mm | −125.495 mm | −89.639 mm |
| red-lw / 14.083333 s | −134.373 mm | −103.658 mm | −95.980 mm |

These are pitch-local values after avatar focus/appearance scale, not all room-scale distances. Table root scale is 0.0255, so its worst −183.760 mm is −4.686 mm along the small table plane's room-space normal. Touchline scale is 0.06; its worst is −7.530 mm in room scale. Player POV uses scale 1, so its −95.980 mm is also the full-scale penetration.

## Bounded correction

`ReplayFarAthleteFloorSupport` prepares the actual far-leg support vertices once during rig binding. It keeps no more than 128 total unique points for the two meshes, including the whole silhouette rather than only a sole anchor. They are stored in hip-local coordinates with the two hip references. Source reads are also bounded (128 raw vertices per leg); invalid, oversized or missing geometry fails softly at setup.

Each pose composes the cached body-root, hips and hip local transforms, then uses bounded support arithmetic. No dynamic mesh readback, visual-bounds query, world-to-local conversion, named hierarchy search or per-frame array allocation is needed in the helper. Only body-root Y changes when the actual far geometry crosses the logical floor: add `max(-minimumY, 0)`, with no new padding. Its X/Z and every authored joint rotation remain unchanged; no downward correction is allowed. Near/mid bindings have no such support cache and retain their existing poses. Static mesh-local transforms and the validated joint hierarchy must remain unchanged after binding; current factory geometry follows that contract.

The 10-case suite checks active ball-action articulation, already-clear far flight, explicitly added authored vertical height, exact reverse/repeated seeks, near/mid parity, cache lifecycle, bounded input admission, whole-silhouette support, visible 120 Hz samples and exact world-ancestor independence. The separate small near/mid floor discrepancy found in Loop 86 is outside this fix.

## An initial implementation error, caught and corrected

The first guard was ineffective: `/private/tmp/replayxi-parallel89-92-mixed-01.xcresult` retained the same 21 floor failures. The next diagnostic run, `/private/tmp/replayxi-ground89-cache-diagnostic-01.xcresult`, ran all 9 tests: 5 passed, 4 failed, with 148 assertions. It exposed an error in the new cache, not a reason to relax the floor limit.

The cache was present, but only held **2 points per rig**. Native mesh data held **58 raw / 44 unique points per leg**; parent identity and finite-value checks were valid. The initial setup used `model.transform.matrix`. These factory entities store a zero quaternion for an identity reset; converting that stored quaternion through raw SIMD produces a zero basis, collapsing every support point. RealityKit's own position conversion preserves the rendered mesh.

Setup now uses `model.convert(position: source, to: hip)` once per bounded source vertex. This is the exact native conversion used to measure the real geometry. No factory quaternion defaults, assets or other entity resets were swept. The cache test additionally requires all source-unique points to survive; whole-silhouette parity tests compare cached and native minima through six varied hip/body transforms, including rotations where a sole is not the lowest point.

Diagnostic attachments:

- `/private/tmp/replayxi-far89-cache-before-01/2C8B9B10-A0F7-4549-AB90-B3398647397F.json`
- `/private/tmp/replayxi-far89-cache-before-01/2ECFC3F2-B6D5-44BA-8C0F-18F0F3C99683.json`

## Exact rewind, without a tolerance escape

The corrected native setup made all scene-floor, action-floor, cache, silhouette and continuity checks pass in `/private/tmp/replayxi-parallel88-94-mixed-01.xcresult`. Eight of the 9 Loop 89 cases passed. The remaining exact-rewind case found 2 assertions: body Y differed by about 1.25 μm, and some converted mesh points also differed after view changes.

The query still used `hip.transformMatrix(relativeTo: root)`. That world/inverse-world calculation could inherit rounding from the previous miniature or room presentation, despite identical local authored poses. A dedicated pre-fix test held the pose fixed and changed only ancestor view transforms. `/private/tmp/replayxi-parallel89-93-prefx-01.xcresult` confirmed one mismatch: −0.09273672 m versus −0.09273404 m.

The helper now caches the validated common body-root/hips references and composes `body.local × hips.local × hip.local`. Those authored rotations are unit quaternions. This removes world ancestors from a rig-local floor calculation; setup still uses RealityKit's native model conversion. Neither the exact-rewind assertion nor any tolerance was relaxed. The oversized-geometry fixture gained a valid parent chain so it continues to reach the same raw-vertex-limit check under the tighter constructor contract.

## Continuity check

Two 0.5 s windows are sampled at 120 Hz: `navy-rb` 11.55–12.05 s and `red-lw` 13.80–14.30 s (122 total samples). Both exercise a real floor correction and its zero-lift join. The visible scene is measured without modifying its graph; a separate test-only rig supplies the raw authored geometry.

The continuity requirement is mathematical, not a guessed physiological speed limit: `max(-height, 0)` is 1-Lipschitz, so the correction cannot jump farther between adjacent frames than the measured raw support minimum changes. Presented body-Y change is also bounded by the authored body-Y change plus that raw support change. Existing floor/articulation tolerances remain intact. Absolute-time rewind stays deterministic; no history, contact state or new gait clock is introduced.

Before attachment: `/private/tmp/replayxi-far89-continuity-before-01/318D74EE-CB29-4099-A1AF-AFEF792235ED.json`. After attachment: `/private/tmp/replayxi-far89-continuity-after-01/E4A73185-9973-4FA1-969C-D364B3195A69.json`.

All 122 raw authored body-Y and support-minimum rows are exactly identical before/after. The first window has 32 negative-support / 29 clear frames; the second has 30 / 31. Actual native after results:

| Window | Max body-Y frame step before | Max body-Y frame step after | Max added lift | Lowest after pitch Y |
| --- | ---: | ---: | ---: | ---: |
| navy-rb | 38.921 mm | 10.207 mm | 92.890 mm | −0.179 μm |
| red-lw | 31.549 mm | 10.637 mm | 92.734 mm | −0.298 μm |

Body translation and lift are rig-local, before appearance/focus scale. These are measured 120 Hz adjacent-frame changes, not a hardware refresh-rate result or a physiological smoothness threshold. The bounded correction does not introduce an independent jump; the existing large authored vertical dips are reduced in these two windows.

## Final native geometry/cache evidence

All 18 scene fixtures are now within 1.550 μm of the logical floor in pitch-local coordinates, versus up to 183.760 mm penetration before. The corrected touch is within 1.669 μm; the six already-clear touch rows are exactly unchanged. Those tiny signed residues are native floating-point conversion error, well inside the unchanged 1 mm assertion limit; no extra lift was added to hide them.

The cache retains **88 unique support points per far rig** (44 per leg) from 116 raw source vertices. In the lifecycle fixture, one standalone rig plus the 22-player scene prepares 23 caches and reads 2,668 raw vertices at setup. All 427 later support queries perform **zero** source-vertex reads or re-preparations. Near/mid remain uncached and preserve their authored poses. The six varied silhouette transforms agree with full native mesh minima within 0.060 μm; all four world-ancestor queries now return exactly the same minimum. Exact reverse/view-repeat geometry also passes.

After attachments:

- Scene: `/private/tmp/replayxi-far89-scene-after-01/05BE514E-8CEE-495F-8E4E-3283573736CF.json`
- Touches: `/private/tmp/replayxi-far89-actions-after-01/1321FAD3-960D-472D-A41C-523F137ADD7E.json`
- Cache: `/private/tmp/replayxi-far89-cache-after-01/39EE2C73-50AB-46ED-8A38-75C2BB89DF96.json`
- Source geometry: `/private/tmp/replayxi-far89-cache-after-01/D04EA9F9-E338-4CC2-B54D-42E2CB30628C.json`
- Whole-silhouette parity: `/private/tmp/replayxi-far89-support-after-01/58A6017A-5401-4CC6-826B-A85AD640C9F7.json`
- World independence: `/private/tmp/replayxi-far89-world-after-01/DE038A09-8C8D-474A-AACB-0F483C75F2D0.json`

## Status and limits

All **10 Loop 89 tests pass** in `/private/tmp/replayxi-parallel89-93-postfix-01.xcresult`. That targeted run is 17/17 overall, including the separate Loop 94 visual export and 6 annotation contract/repair cases. Exact world-ancestor independence and reverse/view-repeat assertions now pass without a tolerance change. Full-suite/Release verification is pending the parent's batch run.

The first full batch, `/private/tmp/replayxi-parallel88-95-full-01.xcresult`, reports 788 passed, 1 optional skip and 1 stale legacy assertion (790 total). `testTabletopSquadLODUsesTelemetryDrivenLimbAnimation` still expected the raw authored body Y, although its `red-lb` 13 s fixture now needs 4.521 mm of far-floor lift. That one old test now retains exact shoulder and body X/Z checks, computes the expected correction on a separate test-owned raw rig, and requires **exact** corrected body Y. It also measures the live far-leg mesh and retains the 1 mm logical-floor bound. This updates the Y contract, not a tolerance escape; the live scene is not mutated by the baseline calculation.

Source and tests are frozen. Native builds and Git backup are run by the parent. This agent ran no Blender job and rewrote no asset; the parent is separately preparing a Loop 94 actual-mesh visual audit. Native scene geometry verifies this bounded correction; it does not establish hardware frame rate or substitute for Vision Pro visual QA. This is a far-silhouette floor guard, not a physical foot-lock or a fix for horizontal foot travel.
