# Loop 52 — Player-bound annotation alignment

## Fixed

Coach Focus held the falling left-back at the contact origin, but its number
tag and attached marks kept following upright telemetry. Running the actual
Swift model code measured **5.105 m drift at 15 s** and **6.618 m at 15.5 s**.
The corresponding shared-origin checks now report **0 m drift**, including
impact recovery, return to normal playback and reverse seek.

`ReplayPlayerPresentation` now supplies the scene's reusable pose map. Player
roots, number tags, attached labels, run/pass endpoints and selected handles
consume that map. Ideal-shape role tags also follow their displayed targets.
Normal first-person replay still uses upright telemetry and free head look;
automatic impacts remain disabled in that view.

Annotation creation, nearest-player snapping, player taps, short-drag recovery,
tracking changes, direct handles and joystick edits use the same presented
origins. Existing scene entities are reused during playback.

## Saving at the boundary

A second regression exposed a legal displayed endpoint at x=33.5 m resolving
to x=35.828 m in upright telemetry. Creation succeeded, but editing and saving
failed. The ideal-shape equivalent displayed z=52 m but resolved to z=56.443 m.
Both failures were captured before the validator fix.

Validation still accepts existing raw-telemetry geometry unchanged. It also
accepts bounded geometry in an exact, active bundled impact context or the
bundled Shape Lab's matching target layout. It does not accept caller-supplied
poses or arbitrary teaching layouts. Stored fallback points, finite values,
player identities, offset limits, times and schema checks remain enforced.
No save format, mark IDs or asset files changed.

## Evidence

- Pre-fix: `/private/tmp/replayxi-alignment51-boundary-repro.xcresult` — both
  boundary regressions failed, with 8 assertions.
- Full native suite: `/private/tmp/replayxi-alignment52-full-01.xcresult` —
  **525 passed, 1 optional skip, 0 failed**.
- All **11** `ReplayPresentedPlayerAlignmentTests` passed: impact/recovery/rewind,
  normal POV, ideal tags, creation/save/restore, tracking, direct-handle Undo,
  joystick commits, both boundary cases and negative validation checks.
- Negative cases cover unknown players, NaN/infinite and excessive offsets,
  out-of-pitch geometry in every permitted context, inactive impacts, uncued
  scenarios and invalid stored fallback points. Legacy raw acceptance remains.
- Python suite: **111 passed, 12 optional skips**. The new input-routing guard
  checks player taps, short drags and direct-handle paths.
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-alignment52-release-01.log`.
- `git diff --check` passed.

Native scene assertions and read-only Swift diagnostics verify this change.
They do not establish headset frame rate or replace headset interaction QA.
