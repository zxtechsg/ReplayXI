# Loop 71 — Large-text secondary controls

## Measured issue

Native UIFont/CoreText probes confirmed that the original fixed label budgets were too small:

- **STANDARD**, caption2 monospaced black: AX1 width 84.07 pt versus 72 pt; AX5 width 128.58 pt. Headline icon line + caption line + 1 pt spacing required 48.73 pt at AX1 and 72.60 pt at AX5, versus the 48 pt height.
- **0.25×**, subheadline monospaced-digit black: AX5 width was about 89.63 pt. Even the permitted 0.8 scale required 71.70 pt, beyond the 64 pt width.

Receipt: `/private/tmp/replayxi-parallel68-70-71-repro-fixed66-67-69-01.xcresult`. The 5-case probe had exactly 2 expected failing cases with 7 assertions; normal-size and source controls passed. JSON font measurements are attached to the test results.

The follow-up covering all seven regular categories found one additional failure: regular XXXL **STANDARD** measured 74.1797 pt versus 72 pt. Other regular metrics passed. Receipt: `/private/tmp/replayxi-parallel72-73-repro-01.xcresult`.

## Fix

A small secondary-control layout policy gives regular preset labels 80 × minimum 48 pt: an 8 pt width increase that fits regular XXXL. Regular rates remain 64 × minimum 60 pt. At accessibility text sizes, presets use 144 × minimum 84 pt; rate labels use 104 × minimum 64 pt with full-size text, not shrinking.

Only secondary speed choices use an adaptive grid. Settings puts its header and ±1s controls above the rates. All seven rates fit the existing accessible deck's width budget, including reserved button-style spacing; the grid can wrap when space is tighter. Base transport and room-fixed placement are unchanged.

## Validation limits

The initial updated 7-case class passed in `/private/tmp/replayxi-parallel71-fixed-01.xcresult`, checking normal and all five AX font categories, secondary-grid wiring and available deck width. The final 9-case class also covers all seven regular text categories and a font/spacing allocation check for the wider preset row. Source parse and whitespace checks pass.

Final full native suite: `/private/tmp/replayxi-parallel73-full-03.xcresult` — 657 total, 656 passed, 1 optional skip, 0 failed. Unsigned physical-device Release: `/private/tmp/replayxi-parallel73-release-01.log` — `BUILD SUCCEEDED`.

UIFont/CoreText measures platform text advances and line heights, not a complete SwiftUI render. The icon calculation is a headline line-box budget, not an SF Symbol pixel-bound measurement. System padding, compression and headset layout still need an interactive pass. The desktop was locked; no screenshot or visual-QA claim is made.
