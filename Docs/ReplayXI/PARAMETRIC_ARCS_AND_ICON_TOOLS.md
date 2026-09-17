# Parametric arcs and icon tools

## Controls

- Draw → curved-arrow icon, then pick two endpoints.
- Select the arc → Adjust. The existing endpoint controls remain available.
- The **Curve** joystick changes curve amount horizontally (0.25 m steps) and angle vertically (5° steps).
- Angle rotates the curve around its actual 3D start-to-end axis. Both endpoints stay fixed.
- The second, cross-arrows icon opens the previous Bend/Lift offsets without losing the angle.
- Plus/minus buttons and named accessibility actions provide the same edits.
- One completed drag or button press is one Undo step. Interrupted previews cancel and stay out of saved reviews.

## Bounds and compatibility

`CoachMarkCurve.rollDegrees` is optional in encoded data; missing values decode to zero. At zero rotation, old bend/lift saves keep their original geometry. Endpoint height, tracking, labels and time visibility still use the existing annotation model.

Curve amount is the midpoint offset before pitch clipping. It scales the existing bend/lift ratio, retaining the original per-axis limits (±12 m bend, 0–4 m lift). Angle is bounded to ±180°.

The control point stays inside pitch boundaries and between 0 and 12 m above the pitch. This keeps a smooth quadratic above the ground. A **Pitch limit** hint appears when clipping affects the requested shape. Raise endpoints to make a downward arc; a turf-level arc cannot dip underground. This is a quadratic curve, not a general multi-knot spline editor.

The tube uses a stable curve-plane frame, avoiding abrupt ring twists when a tilted curve crosses the old vertical threshold. Rotation changes invalidate the mesh/picking geometry; unchanged playback and pure player-bound translation still reuse the mesh.

## UI

Base Draw and Tools buttons, plus the six drawing tools, are icon-only. The speed button keeps only the meaningful rate (for example, 1.5×). Hover help, accessibility names/actions, selection colour, hit areas and room-fixed placement remain. The current player number and drawing-step prompt remain because they convey state, not duplicate tool names.

## Verification

Added tests cover old JSON and exact old samples, upright arcs, elevated chord-axis rotation against independent Rodrigues math, pitch/floor bounds, saved-angle round trips, Undo, native mesh/picker updates, atomic edits and gesture ownership. Updated native font probes measure icon-only Draw/Tools and the single-line speed control, rather than the removed captions.

The native integration run `replayxi-native125-integration-05` passed the seven scene-admission tests, three recorded-ball scene tests, two arc-pad capture tests and 21 updated text-metric tests. The pad captures use the actual SwiftUI component, not a mock.

Inspected normal text, largest accessibility text and negative-angle **Pitch limit** captures from `replayxi-native125-integration-06`: no clipped labels or buttons. The vertical arrow initially rendered as a blue emoji tile. Explicit Unicode text presentation now keeps both direction arrows monochrome; the default pad capture in `/private/tmp/replayxi-native125-full-02-attachments/2DADA119-B9C6-4B6E-AEBF-33D70A540E23.png` verifies the fix.

These are offscreen panel checks, not headset or gesture QA. The live simulator also displayed the icon deck and arc panel, but the available UI automation could not operate its window. Hand-tracked drawing, dragging and comfort still need device testing. Source parsing and whitespace checks passed; a full-suite rerun is separate from these focused receipts.
