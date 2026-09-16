# Loop 85 — reachable Shape annotation tools

## Confirmed issue

The Shape status branch always won before annotation drafting or selection.
A restored player/time-bound mark could show its 3D handles and suspend player
picking, while its inspector and Close control remained hidden. Normal Shape
also had no in-room Draw entry. Store authoring, save and geometry operations
were valid; the control-deck route was missing.

## Bounded change

- One existing Draw button opens the shared tool strip from Shape status.
- Drafts use the existing drawing/Cancel shelf. Selected marks use the existing
  inspector, labels, tracking, duration, endpoint controls, events and history.
- The Shape workspace has a scrub-only timeline above those tools. No match
  Play, speed or POV controls are added. Physical stations still take precedence.
- The stable deck host now owns the existing selection/scenario cleanup and
  review-index observers for both modes. Close/Back cannot unmount a held
  timeline or joystick; their hint asks the user to finish the current gesture.
- If a preset leaves its visible time window during a scrub, its selection
  clears but the owning workspace stays mounted until the transaction ends.
  Tracking-loss cancellation and explicit draft Cancel remain in place.

No save-schema, player binding, room placement, local-only or free-look changes.
No duplicate annotation editor or new transaction state.

## Verification

Pre-fix receipt: `/private/tmp/replayxi-parallel83-85-mixed-01.xcresult` and its
matching log. The seven initial `ReplayShapeAnnotationDeckTests` had four
expected failures with 15 assertions; three controls passed. The full mixed
batch had 20 tests: 16 passed and these four failed.

The final class has ten cases covering restored bound marks, both draft phases,
Back/submenus/Erase-to-Undo, held geometry and scrubbing, physical precedence,
normal Match/Shape routes, preset expiry while scrubbing, and source wiring of
the shared entry, shelves and cleanup. All ten passed in the targeted mixed
receipt `/private/tmp/replayxi-parallel85-87-mixed-01.xcresult`. This is a
Loop85-targeted result, not a clean full-suite receipt. The later full native,
Release and Python runs pass; see `VERIFIED_BATCH_78_87_2026-09-17.md`. No physical-headset or live
gesture validation is claimed.
