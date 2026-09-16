# Loop 43 — real annotation Undo/Redo

## Changes

- Undo now reverses the most recent committed annotation action. Previously
  it only removed the newest created mark, even if the latest action was an
  edit or erase. The compatibility Undo entry point uses the same new history.
- Added Redo. Adding, labelling, retiming, duration, player binding, spatial
  elevation, geometry, erase and Clear are reversible. Original teaching
  overlays stay protected. Exact mark IDs, order and metadata are restored.
- One completed joystick or direct-handle drag makes one history entry, not
  one per sample. Cancelled gestures add none. Undo/Redo is blocked while a
  drawing, timeline or geometry gesture owns input, and pauses playback.
- Transport/POV actions and failed/no-op edits do not erase Redo. A new
  committed annotation change does. External state replacement cannot be
  overwritten by an unrelated history entry.
- Erase and Clear open the retractable history shelf immediately. The shelf
  remains reachable when the last mark has been removed, so Undo or Redo is
  not hidden behind a disabled Edit button. Buttons identify the action:
  Undo add/edit/erase/clear and their Redo equivalents.
- Draw and overlay controls no longer rearrange the deck during a timeline
  pinch. Erase/Clear cannot compete with an owned gesture.
- Removed misleading local messages claiming annotations were shared with a
  squad. This remains an on-device, local-only editor.

## Scope and bounds

History belongs to the current open scenario/session. Switching/resetting the
scenario or loading a saved review starts a fresh stack without deleting that
scenario's saved marks. Undo history itself is not serialized; the committed
result of Undo/Redo is autosaved normally.

Both stacks together retain at most 32 actions and 2,048 mark values. Large
Clear snapshots may reach the mark-value limit before 32 entries. Repeated
playback updates do not grow history. No asset/render budgets or network
capabilities were added.

## Verification

- Focused history/gesture transaction checks: **37 passed**, no failures/skips.
  `/private/tmp/replayxi-undo43-targeted-02.xcresult`.
- Full Simulator suite: **418 passed, 1 optional skip, 0 failed (419 total)**.
  `/private/tmp/replayxi-undo43-full-01.xcresult`.
- Unsigned visionOS Release build passed:
  `/private/tmp/replayxi-undo43-release-01.log`.
- Python pipeline checks: **107 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-undo43-python-01.log`.
- Regression coverage includes exact erase/Clear recovery, one-step drags,
  cancellation, gesture ownership, redo invalidation, scenario/save isolation,
  autosaved committed results, external replacement protection, history memory
  bounds and control-shelf reachability after the last mark disappears.
- The first compile exposed a wrong test-helper method name for height nudges;
  it was corrected before the successful targeted/full runs.

Live desktop interaction was not rechecked while the Mac was locked. Source
layout/control checks and Simulator logic tests are not physical hand, comfort,
or frame-time validation. The 9am timed goal remains active.
