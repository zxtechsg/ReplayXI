# Loop119 — native replay scene audit

Test-only work in one method of `ReplayRealityRendererAuditTests.swift`.
No application, camera policy, asset or annotation behaviour is changed.

## Scene contract

The capture uses `PitchSceneFactory` at13.6 s in the existing32-second
`eleven-eyes` authored demo. The original bundled Blender pitch/ball, one near
skin, three admitted low skins,18 static-faced far rigs,22 player labels and
default timed coaching marks are prepared through the normal providers.
The scene contains all22 players; enabled hierarchy counts are **not** counts
of players inside the camera frustum or hardware draw calls.

Touchline retains its actual0.06 scale,90-degree Y rotation and room position
`[0,0.02,-4.1]`. The fixed audit camera uses the converted label observer at
pitch X−70/Z0, room Y1.6 m, with50-degree vertical field of view, aimed at the
actual presented ball. There is no recentering of players or annotation paths.
Fixed diagnostic lights are used, not physical-room illumination.

The pass “Break the first line” and run “Outside overlap” are visible at13.6 s;
the “Late-arrival pocket” remains hidden until16 s. Tests verify those actual
flags, arrow geometry, label visibility and projected arrow positions.

## First receipt and corrected test premise

`/private/tmp/replayxi-gate117-joystick118-scene119-after-01.xcresult` captures
the first attempt: one method fails two assertions. The test wrongly expected
Touchline turf to be enabled and more than5,000 non-background pixels.

Source inspection confirms the existing factory intentionally enables turf
only for Tactical Table and Player POV. Touchline is a transparent field-line
overlay. The failed PNG actually contains the pitch lines, player group,
cyan pass and orange run; it is not an empty scene. The native receipt has
2,503 non-background pixels,79 sampled quantized colours,1 near/3 low/18 far
players,22 labels and2 visible marks. Calibration passes Display P3, top-first
rows, maximum channel error1. These facts do not establish a product defect.

Initial exports:
`/private/tmp/replayxi-scene119-native-before-01/`.
PNG `586663B5-DEA7-4EC6-BD63-609EF3EBA3BD.png`;
metadata `0D107D43-81FA-4C4F-96EF-9DD4B076BDC6.json`.

## Revised controls

The test now preserves and asserts Touchline's turf-OFF behaviour. It keeps
the same camera and renders a separate negative control with only the marks
root disabled, restoring its exact original flag through `defer`. Timed marks
must change rendered pixels, while additional player/pitch pixels remain.
The colour-variety and full structural checks remain. This replaces the
unsupported turf-area premise with a direct visual-contribution test; it does
not tune the pixel threshold down to the observed count.

A separate real Tactical Table transition verifies turf-ON using the normal
factory update. Its fixed room camera is `[0,1.6,0]`, aimed at the existing
table origin, at the same50-degree field of view. The original greater-than-
5,000-pixel control applies to this actual full-turf presentation. No field is
forced into Touchline. Each positive view exports its own camera/root matrices,
ball coordinates, active marks, current counts, hashes, calibration and PNG.

## Passing receipt

The revised method passes in
`/private/tmp/replayxi-scene119-after-zone120-before-01.xcresult`. The mixed
batch has five cases: three passed and two expected Loop120 pre-fix failures.
This is a passing scene audit, not a clean whole-app-suite claim. Source parse
and whitespace checks also pass.

Exports: `/private/tmp/replayxi-scene119-native-after-01/`.

- Touchline PNG `990FDBFF-84B4-4B02-9846-C43F6C1C713D.png`;
  JSON `29BB28F3-17DD-4A6C-92C8-ECABD5F715A6.json`.
- Tactical PNG `7FEE4794-B206-4A4D-B24C-FCD67D756BCF.png`;
  JSON `649FEC54-EDCD-4203-9479-5B917A127156.json`.

| Actual presentation | Turf | Foreground pixels | Sampled colour buckets | Hierarchy-enabled models |
| --- | --- | ---: | ---: | ---: |
| Touchline |Off |2,503 |79 |180 |
| Tactical Table |On |92,241 |88 |182 |

Hiding only the Touchline marks changes224 rendered pixels; the original flag
is restored. Its positive image remains at the same2,503 foreground pixels as
the first capture: the test premise changed, not the displayed scene. Both
positive captures retain22 players,1 near/3 low skins,18 far faces,22 labels
and2 timed marks. Both use Display P3/top-first/max-error1 calibration.

Both final images were inspected. Touchline shows the transparent field lines,
group and coloured passing/running arrows. Tactical shows the actual striped
turf, field layout and goals, with the right-side coaching move visible in
context. Small distant players and text cannot be judged for fine readability
at this resolution. No scene elements were moved or enlarged for either view.

## Limits

These are512-pixel native offscreen composition checks, not SwiftUI screenshots,
live head tracking, passthrough, headset readability or performance verdicts.
Touchline text and people are small in the512-pixel overview. The capture does
not imply that every enabled player or label is legible in that image, and it
does not reconstruct a real match from video.
