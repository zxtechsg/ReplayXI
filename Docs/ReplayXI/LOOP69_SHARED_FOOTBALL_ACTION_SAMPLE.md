# Loop 69 — Share football-action samples

## Change

The scene inferred the same foot-to-ball action for skin admission and again for
each procedural body. Near and far rigs now receive that first sample, including
the no-touch result. No extra cache or frame-dependent state is introduced.

The existing skin, touch suppression during procedural impacts, Shape behaviour,
player/ball tracks and animation equations are unchanged. DEBUG-only counting is
used by the regression tests; the counter is absent from Release.

## Evidence

- Before: five cases; two work-count cases failed, three articulation/Shape/impact
  controls passed. `/private/tmp/replayxi-action69-repro-01.xcresult`
- Procedural match views previously inferred **44 actions per update** in Table
  and Touchline, or **43** in POV. With skinned athletes: **43 / 43 / 41**.
- After: all **5 cases passed**, inside the 17-case mixed pre-/post-fix run
  `/private/tmp/replayxi-parallel66-67-repro69-fixed-01.xcresult`. Its seven failures
  belong only to the intentionally pre-fix ball-rolling and transport tests.
- Each match view now samples **22 times**, once per player. Shape remains **0**.
- Every near/far joint transform matches the original independently sampled
  reference at control, pass, cutback and stationary moments, including reverse
  seeks. Procedural impact articulation also matches exactly.

This is a measured reduction in duplicated calls, not a measured headset FPS
improvement. The final full suite passed: **656 passed, 1 optional skip, 0 failed**
in `/private/tmp/replayxi-parallel73-full-03.xcresult`. The unsigned device Release
build also passed in `/private/tmp/replayxi-parallel73-release-01.log`.
