# Loop 82 — Active POV versus retained player focus

## Issue and fix

After entering a player POV and switching to Tactical or Touchline, Store intentionally retains the player ID for focus and quick return. The immersive roster still marked that shirt as selected, showed its POV badge and named it as the current player view. The dashboard already distinguished these states.

Four UI guards now require first-person mode: the numbered compact label, active-player accessibility wording, roster POV badge and selected shirt trait. Other views show the existing **POV PLAYER** action and **Choose player point of view** accessibility label. Both XIs remain available; choosing any shirt still enters that player's free-look POV. No camera action, Store state or selection barrier changed.

## Validation

- Pre-fix receipt: `/private/tmp/replayxi-parallel78-82-mixed-01.xcresult`. Loop82's 2 source cases failed with 4 assertions; all 3 Store controls passed. The mixed run was not an overall clean result.
- Controls verify retained focus after leaving POV, re-entering the retained player's POV paused at the same time, access to both teams and navigation-only reselection of an already active POV.
- UI checks inspect private SwiftUI wiring, not rendered interaction. Tests and tolerances were unchanged for the fix.
- All 5 post-fix cases pass in `/private/tmp/replayxi-parallel80-84-mixed-01.xcresult`. Its unrelated pre-fix card-text failures mean the mixed run is not a clean full-suite result. The later full native suite and Release pass: see `VERIFIED_BATCH_78_87_2026-09-17.md`. Source parse and whitespace checks pass.

Desktop locked: no interactive headset or visual-QA claim.
