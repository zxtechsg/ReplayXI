# Loop 75 — Clear confirmation during a timeline scrub

## Issue and fix

Source sequence: create a coach mark, open Tools → Edit marks → Clear all…, then hold the main timeline scrub and tap Clear with the other hand. Clear remained enabled. Store correctly rejected the competing edit, but the UI closed the confirmation and reported **MARKS CLEARED** while the marks remained.

Clear now uses the existing `canChangePlaybackView` gate, matching the entry button. Its callback rechecks admission, coach role and mark count before clearing or changing UI state. A blocked-action hint explains how to continue. Cancel only closes the confirmation; the owning timeline can still continue, finish or cancel. Store behavior, saved data and normal Undo are unchanged.

## Validation

- Pre-fix receipt: `/private/tmp/replayxi-parallel74-77-repro-01.xcresult`. The 2 expected source-wiring cases failed with 4 assertions. Scrub ownership and Cancel/rail controls passed.
- The normal-clear control also exposed a test-only title mismatch: existing history calls removal of one mark **Undo erase**, not **Undo clear**. That expectation was corrected; exact mark preservation and Undo restoration assertions remain.
- The 5-case class combines UI source-wiring checks with real Store rejection/normal-clear controls. It does not execute private SwiftUI callbacks.
- Targeted post-fix receipt: `/private/tmp/replayxi-parallel74-75-77-fixed-01.xcresult` — 39 passed, 0 failed, including all 5 Loop75 cases.
- Final full native suite: **675 passed, 1 optional skip, 0 failed** (676 total),
  `/private/tmp/replayxi-parallel77-full-01.xcresult`.
- Unsigned device Release: **BUILD SUCCEEDED**,
  `/private/tmp/replayxi-parallel77-release-01.log`. Source parse and whitespace checks pass.

Desktop locked: no interactive, screenshot or gesture-feel QA is claimed.
