# Loop 56 — Physical placement POV boundaries

## Fixed

During physical placement, tracking loss exposes the ideal overview. Tapping a
fallback player called `openLocalPlayerPOV`, which changed the camera to first
person while placement, its anchor and consent remained active. The coach-focus
route could do the same. Ending that inconsistent state left the camera in POV.

The fallback scene also used ideal role targets while annotation input used raw
telemetry. At 16 s, the input/render gap was **4.452 m for RB**, **1.000 m for RW**
and **6.767 m for RCM**. Ready placement hid the players, masking the mismatch.

Both POV entry points now obey the existing physical-placement camera lock.
Station selection stays available; ending the drill restores access to POV.
The shared positional context uses ideal targets during placement, keeping input
and rendering aligned through ready, lost, ready and end transitions. Actual
Swift-source checks now report **0 m drift** for all three roles. No additional
tracking-readiness state was introduced.

Local-only operation and normal first-person free look are unchanged. Impact
view-switch checks still keep player bodies and annotation origins aligned.

## Evidence

- Pre-fix: `/private/tmp/replayxi-boundaries55-repro-01.xcresult` — **3 of 5**
  placement tests failed, with **15 assertions**; both control cases passed.
- Post-fix: all **5** `ReplayPlacementPresentationSafetyTests` passed: fallback
  player tap, camera entry points, ready/lost/end origins, station selection,
  and view switching during an active impact.
- Combined native suite: `/private/tmp/replayxi-parallel55-full-01.xcresult` —
  **556 passed, 1 optional skip, 0 failed** (557 total).
- Python suite: **111 passed, 12 optional skips**.
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel55-release-01.log`.
- `git diff --check` passed.

These are native scene tests and actual-source diagnostics, not physical
headset validation. No headset interaction, tracking-loss UX or frame-rate
measurement is claimed.
