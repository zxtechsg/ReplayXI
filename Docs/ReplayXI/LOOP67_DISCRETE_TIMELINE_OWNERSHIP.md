# Loop 67 — Discrete timeline ownership

## Issue and fix

While a timeline pinch was held, Previous/Next cue, event chips and ±1s buttons reused the owning scrub rail's permissive gate. They stayed enabled even though Store correctly rejected competing seeks. A mark chip changed annotation selection and visibility before that rejection, opening the inspector without reaching the selected moment.

Discrete navigation now uses the existing `canChangePlaybackView` gate. Cue/mark selection checks it before changing selection or overlays. Jump, repeated stepping and accessibility adjustment callbacks also check it before touching transport.

The owning rail keeps its separate gate so a held pinch can continue, finish or cancel normally. No global Store policy, room-fixed placement, player models or saved data changed. No keyboard shortcuts or context menus exist on these specific transport paths.

## Validation

- Pre-fix combined receipt: `/private/tmp/replayxi-parallel66-67-repro69-fixed-01.xcresult`; 17 total, 10 passed and 7 failed across the parallel repro classes.
- Loop67's 6 cases: exactly 3 expected failures with 13 assertions; all 3 controls passed.
- All 6 Loop67 tests passed in `/private/tmp/replayxi-parallel68-70-71-repro-fixed66-67-69-01.xcresult`. Source parse and whitespace checks pass.
- Final full native suite: `/private/tmp/replayxi-parallel73-full-03.xcresult` — 657 total, 656 passed, 1 optional skip, 0 failed.
- Unsigned physical-device Release: `/private/tmp/replayxi-parallel73-release-01.log` — `BUILD SUCCEEDED`.

Four tests inspect SwiftUI callback/disabled-state wiring; two test real Store transport ownership and normal seeks. They do not execute private UI callbacks or replace an interactive headset pass. The desktop was locked, so no visual or gesture-feel QA is claimed.
