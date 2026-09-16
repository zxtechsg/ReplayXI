# Loop 68 — Shape comparison keeps an unfinished annotation stable

## Reproduced defect

In local Shape Focus, start a Run from #2 (`navy-rb`) in Problem at 14 s. Before placing its destination, choose Ideal, then place the end at `(28, 34)`.

- The comparison advanced to 16 s while drawing remained active.
- The player moved from `(31.36169, 25.538822)` to `(31, 29)`: **3.480025 m** from the saved draft start.
- The completed run used 16 s and lost both player anchors. It could still be saved.
- The reverse comparison and selecting the current stage from another timestamp could also move an unfinished draft.

The memory-only diagnostic used the actual Store and scenario sources. Problem/Ideal controls were enabled during drawing; `setShapeFocusStage` checked adjustment/scrub ownership but not drawing ownership.

## Bounded correction

Stage changes now use the existing drawing-aware playback/view gate. Both the immersive panel and dashboard disable their Problem/Ideal selectors and Reveal/Compare buttons while drawing, scrubbing, or adjusting a mark. Committing or cancelling releases the controls.

Annotation geometry, save schema, room-entry draft access, physical placement and free-look semantics are unchanged.

## Regression coverage

`ReplayShapeDraftContinuityTests` contains four cases:

1. Empty drafts reject all stage comparisons without moving time or players.
2. Started drafts retain their original moment and player binding in both directions.
3. Cancel restores comparison while preserving committed marks and Undo/Redo.
4. Completed runs survive comparison, Undo/Redo, and saved restoration.

Three Python source-wiring checks cover the Store gate, every comparison button, and continued access to room entry during a draft.

## Verification

- Pre-fix: two native cases failed with **22 assertions**; Cancel and completed-run controls passed. Receipt: `/private/tmp/replayxi-parallel68-70-71-repro-fixed66-67-69-01.xcresult`.
- Post-fix: **all four native cases passed** in `/private/tmp/replayxi-parallel71-fixed-01.xcresult`. That combined targeted run had 164 passes and one unrelated ball-track float-fixture failure; it was not a clean full-suite receipt.
- Final native suite: **656 passed, one optional skip, zero failures** (657 total). Receipt: `/private/tmp/replayxi-parallel73-full-03.xcresult`.
- Unsigned physical-device Release: **BUILD SUCCEEDED**. Receipt: `/private/tmp/replayxi-parallel73-release-01.log`.
- Python suite: **114 passed, 12 optional skips, zero failures** (126 total), including the three new source-wiring checks. Receipt: `/private/tmp/replayxi-parallel73-python-01.log`.
- No headset validation is claimed.
