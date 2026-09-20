# Run 154 — player label setup

Status: corrected 26-test focused run, optimized native integration, full Debug regression on visionOS 26.5 and unsigned device Release build passed. No material timing gain or cleanup fix claimed.

## Evidence-led candidate

Run153 identifies labels/selection as the largest cold-build stage on all 20 measured roots. The existing 64-entry text cache reuses meshes but queries native visual bounds for every new glyph entity, including cache hits (44 glyphs per full squad).

Cache the exact initial centering offset with each cached mesh. Keep fresh entities and materials, identical cache keys/eviction limits, hierarchy, input/hover/accessibility data and text generation. Do not change collision-shape ownership, selection/facing helpers or annotation-card extent measurement in this candidate. Reuse avoids known repeated work; the timing gain still needs measurement.

Required checks: native centering oracle, both teams/all five rosters, warm repeated labels, bounded eviction/revisit, existing text/label/clearance regressions and same-runtime optimized cold-stage comparison.

## Pitch visibility audit

The black turf area in the run152 slow-run diagnostic captures is intentional fixture policy, not evidence of missing textures. Those tests use `.touchline`, which hides the turf while keeping pitch markings. Their renderer has a black clear background. The older first-person native support capture `/private/tmp/replayxi-cycle150-moving-captures/042B2B90-73DE-4AF6-AA9B-7A69707CDCF8.png` shows green textured turf with the same black clear background. Add a narrow all-view visibility guard; do not change production pitch visibility or rewrite the old visual evidence.

## Cleanup investigation

The exact run152 binary is undergoing a bounded ten-iteration debugger reproduction. Tracepoints log the existing root/child detach path without executing app getters or changing ownership. A non-reproduction is not a cleanup fix; the full152 crash remains recorded.

The ten repeats passed, followed by a passing unchanged-binary ordered145→147→149 cohort. The latter probe recorded all four149 cleanup/snapshot-release returns, with no weak-error or bad-access stop; process91563 exited0. Both sessions are closed. Retain the original failed full run; this is negative reproduction evidence, not a fix.

## First focused run

`/private/tmp/replayxi-cycle154-labels26.xcresult`: 22 passed, four new text tests failed. All reported failures compare equivalent native RGB colours to UIKit colours using object equality (RGB white vs grayscale white; RGB blue vs named UIKit blue). Geometry, cache-count, pitch-visibility and existing regression assertions passed. The correction will check successful RGBA extraction and components while retaining material/type/tone-map/layout guards; production colours are unchanged.

## Corrected checks and timing

- `/private/tmp/replayxi-cycle154-labels-fixed26.xcresult`: 26 passed/0 failed, Debug Local38. Both colour conversions must succeed; finite RGBA components agree within 1e−6. Type/tone-map/layout/hit-target/cache guards remain. Immediate same-squad repeat: 44 cache hits, zero centering-bounds queries. Annotation-card extent queries remain unchanged.
- `/private/tmp/replayxi-cycle154-stages26.xcresult`: two native integration tests passed using optimized Debug, same visionOS 26.5 runtime/test order as clean run153. Exact initial graph/resource/evaluation fields are preserved across all 20 roots. The 650 sampled motion rows and joint maxima agree; tied peak-player identifiers can vary because the diagnostic visits an unordered dictionary. Equal peak values/times are not a motion regression.
- Excluding the first root (19 roots): label-stage median 33.246→33.114 ms; whole-root median 65.166→65.024 ms. Paired median label delta −0.170 ms; both faster and slower roots occur. Label p95 93.308→85.536 ms is the maximum for this small set and reflects one City45 outlier. The first root is slightly slower. **A single A/B does not establish a convincing material or repeatable wall-time gain.** The known reduction is repeated centering-query requests, with a small offset stored in each already-bounded cache entry.
- Warm-update changes are tiny/mixed: median paired case deltas −0.0025 ms fast-only, −0.0041 ms enabled. Centering is not on the warm update path; do not attribute these changes to the patch or infer FPS.
- Stage receipt: `/private/tmp/replayxi-cycle154-stages26-captures/24A2B4CD-3C37-4C82-B5E4-F37A4689423F.json`.
- Device Release build passed: `/private/tmp/replayxi-cycle154-release.log`. Full regression passed: `/private/tmp/replayxi-cycle154-full26.xcresult`, 1,542 passed, two intentional skips, zero failed. This clean run does not resolve the intermittent full152 cleanup crash.
- Local38 holds the new Debug build; Local37 remains the exact run152 crash-reproduction binary and is not overwritten.
