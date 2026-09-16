# Loop 59 — Decision lanes match displayed players

## Fixed

In Coach Focus at 15 s, choosing the opposing left-back, switching to Table
and opening Decisions placed all four passing lines **5.105 m** from his
displayed body. The receiver version put the target ring at the upright
telemetry position instead of the fallen player.

Current lane metrics used those raw positions too. For `red-lb` → `red-lw`,
the card reported **1.278 m / tight**, while the displayed spacing was
**2.098 m / clear**.

The decision model now accepts the same presentation context as the scene.
It uses those positions for pass distance, option distance bounds, defender
clearance, target pressure and lane availability. Both UI snapshot producers
pass that context. The scene reuses its existing player pose map for passing
line endpoints, receiver rings and their hit targets.

Historical scan, receiving orientation, observed ball destination, coach
suggestion evidence and provenance still use the original tracks. Normal
first-person free look remains unchanged. No saved schema, telemetry, player
identity, local-only behaviour or render-slot limit changed.

## Evidence

- Pre-fix: `/private/tmp/replayxi-parallel58-repro-01.xcresult` — **3 of 4**
  decision tests failed, with **50 assertions**. The historical/free-look
  control passed.
- `ReplayDecisionPresentationAlignmentTests` covers fallen source and receiver
  endpoints, exact **15 → 16 → 15** return, spacing/defender/availability
  consistency, preserved evidence and unchanged normal POV.
- Actual-source Swift diagnostics after the fix report **2.097512 m / clear**
  for the affected lane, exact snapshot return after rewind, unchanged
  historical fields and unchanged normal POV.
- Targeted native run: `/private/tmp/replayxi-decisions59-fixed-01.xcresult` —
  **24 passed, 0 failed**, including all four new tests plus existing decision
  review and spatial-focus tests.
- Combined targeted run: `/private/tmp/replayxi-parallel62-fixed-01.xcresult` —
  **56 passed, 0 failed**, including all four decision alignment tests.
- Full native suite: **606 passed, 1 optional skip, 0 failed**. Device Release
  build passed. See [batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).
- `git diff --check` passed.

No physical-headset interaction or frame-rate validation is claimed.
