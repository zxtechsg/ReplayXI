# Loop 79 — Full-size annotation duration choices

## Evidence and change

Native CoreText measurements covered all seven regular and five accessibility text categories. The previous duration labels **fit at their allowed 0.78 scale**; no clipping bug was established. At the largest accessibility category, “TO END” measured 106.58 pt against its 104 pt label budget. This meant its requested full font size could be reduced.

Accessibility layouts now give duration choices a separate adaptive row beneath the header and current length. Timed choices receive 80 pt, “TO END” receives 128 pt, minimum label height is 64 pt, and minimum text scale is 1. The regular compact row and its existing budgets are unchanged. Grid cell budgets include the same 48 pt native button-style allowance used by other secondary controls.

All five choices, timing validity, selected-state disabling, gesture-ownership guard, and the existing Store action are unchanged. This is a large-text accessibility improvement, not a new playback or save format.

## Validation

- Before: `/private/tmp/replayxi-parallel78-80-repro-01.xcresult`. Both native font-measurement cases and source wiring passed. The desired full-size/adaptive policy failed two assertions in one case.
- Font attachment: `/private/tmp/replayxi-timing79-before-ax-01/884D96F4-B713-4020-B825-0EB2FA4BD2AC.json`.
- Added a regular-layout preservation check and live adaptive-shelf wiring assertions. All 60 duration/category text advances are checked against the actual layout constants.
- All 5 post-change cases pass in `/private/tmp/replayxi-parallel78-82-mixed-01.xcresult`, including the 60 font measurements at the revised live budgets. The mixed bundle also contains unrelated pre-fix failures. The later full native suite and Release pass: see `VERIFIED_BATCH_78_87_2026-09-17.md`.

Text advances and source wiring do not prove rendered SwiftUI placement or headset reach. The desktop is locked; interactive UI, visual layout and VoiceOver use remain unverified.
