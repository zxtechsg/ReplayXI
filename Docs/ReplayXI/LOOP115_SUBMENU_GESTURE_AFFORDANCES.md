# Loop 115 — truthful submenu availability

## Reproduced mismatch

Open the POV roster, or a selected mark's Label/Follow submenu, then hold the main timeline. The submenu stays visible. Its choices appeared available even though the Store rejects camera, label and player-binding changes during a held transaction. Existing callbacks preserved data, but the controls gave no accurate availability cue.

Pre-fix native receipt: `/private/tmp/replayxi-ui115-before-head116-01.xcresult` and `.log`. Three UI-wiring cases failed as expected; all four Store/owner/normal-action controls passed. Source checks prove the private SwiftUI wiring, not an interactive UI event simulation.

The first source harness also matched the outer view's same-named POV helper for its callback-order assertion. That selector mistake was narrowed to the `ImmersiveControlDeck` source before post-fix verification; gate assertions are unchanged. The deck's POV callback already had the correct guard. The missing disabled states and hints were real, separate findings.

## Narrow fix

- Roster shirts now use the existing POV disabled policy and a blocked gesture hint.
- Label, follow-player and fix-to-pitch choices use the existing `canChangePlaybackView` policy, with matching accessibility hints.
- Label/tracking callbacks recheck that policy before calling Store, protecting delayed actions. POV already had its callback guard.
- The timeline's own update/finish gate and all close/cancel routes are unchanged. No Store, save, geometry, sizing or navigation redesign.

Seven regressions cover wiring plus real Store scrub commit/cancel, direct/joystick ownership, normal opponent POV, labels/player binding and exact Undo. All seven pass in `/private/tmp/replayxi-ui115-after-head116-02.xcresult` (18 targeted tests passed overall). Syntax parsing passed.

Full integration passed in `/private/tmp/replayxi-parallel115-120-full-01.xcresult`: 914 total, 913 passed, 1 optional skipped, 0 failed. Unsigned device Release passed; see [batch receipts](VERIFIED_BATCH_115_120_2026-09-17.md). No interactive visual or headset QA was possible while the desktop was locked.
