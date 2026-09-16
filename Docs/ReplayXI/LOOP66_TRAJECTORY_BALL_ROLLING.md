# Loop 66 — Ball rolling follows the replay path

## Change

The ball previously rotated at a fixed 1.8 radians per second, even during the
motionless 27–32 s tail. Rotation now follows horizontal travel distance and
direction, using the nominal 0.11 m radius. Each segment continues the preceding
orientation; stationary segments stop rotating. The grounded Shape marker keeps
a fixed orientation.

One immutable sampler is prepared per match root. Queries binary-search its
precomputed segments, without rebuilding arrays or accumulating frame history.
Seek, pause, reverse order and view changes return the same orientation.
The sampler belongs to the root, not the separately evictable annotation cache.

Malformed input fails to a unit identity rotation. Preparation is bounded to
65,536 strictly timed finite keyframes. Long-segment angles are reduced in Double
before conversion to Float. Telemetry, positions, heights, scales, shadows,
assets, draw limits and saved formats are unchanged.

Airborne rotation uses projected horizontal distance too. This is a visual
approximation, not measured spin or reconstructed ball physics.

## Verification

- Original scene regression: four affected cases failed, two deterministic
  controls passed in
  `/private/tmp/replayxi-parallel66-67-repro69-fixed-01.xcresult`.
- The first implementation exposed a zero-quaternion prefix: `simd_quatf()`
  contains four zeroes, not an identity rotation. Explicit unit identity is now
  used throughout this sampler, and tests require unit length rather than
  allowing zero-versus-zero comparisons.
- A fixture's exact whole-pose comparison also detected existing 0.000000015 m
  height rounding at the 27 s endpoint. Its X/Z check remains exact and height
  uses a 0.000001 m tolerance. Rotation assertions were not relaxed; BallTrack
  was not changed.
- Final targeted result: **all 13 cases passed** in
  `/private/tmp/replayxi-parallel72-73-repro-01.xcresult`. Its six failures belong
  only to the intentionally pre-fix impact, workspace and regular-text probes.

Coverage includes four travel directions, composed turns, stopped segments,
pass-boundary continuity, exact seek/view repeatability, malformed/scalar/count
bounds, many-turn precision, explicit airborne convention, root cache reuse and
root-lifetime release. The final full suite passed: **656 passed, 1 optional skip,
0 failed** in `/private/tmp/replayxi-parallel73-full-03.xcresult`. The unsigned
device Release build also passed in `/private/tmp/replayxi-parallel73-release-01.log`.

No headset frame-rate or visual comfort claim is made.
