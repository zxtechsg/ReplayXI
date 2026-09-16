# Loop 58 — Physical drill safety

## Changes

- Logical physical placement is annotation read-only, including tracking loss. Drawing, labels, preset marks, handle acquisition, geometry, metadata, delete, clear, undo and redo cannot change hidden annotations. Cancellation stays available.
- Placement rejects an unfinished draft, scrub or geometry adjustment without moving its timestamp. The setup panel explains the blocker and offers **Cancel annotation** for a draft. Ordinary room entry still preserves a paused draft.
- Placement rechecks admission after asynchronous anchor creation. A rejected attempt removes only its exact new anchor, retains request ownership checks and reads the current blocker after cleanup.
- **End drill** restores unfinished transaction checkpoints, cancels a draft, pauses, and retires only the selected anchor. Committed marks and undo history survive. Late direct-handle endings require an existing preview before they can commit.
- A stale anchor-removal callback now checks the selected anchor before cancelling anything. It cannot roll back a newer tabletop scrub or annotation adjustment.
- Station selection reports **Role station**, not **Player POV**. Rejected selection keeps its existing role and gesture explanation.
- Scene marks and handles remain hidden throughout physical placement, including ready → tracking lost → ready. This uses the logical placement state rather than the temporary rendering fallback.

The normal physical-drill deck already hid drawing and transport controls. This fixes state/callback paths and tracking-loss exposure; it does not add physical-room drawing or remove replay annotation tools.

## Validation

- Initial Store repro: 11 tests; 10 failed with 50 assertions, non-coach control passed. Receipt: `/private/tmp/replayxi-parallel58-repro-01.xcresult`.
- Scene repro: 2 failed assertions for geometry/handles during tracking loss. Receipt: `/private/tmp/replayxi-physical58-visibility-repro-01.xcresult`. Fixed scene class: all 5 passed in `/private/tmp/replayxi-physical58-visibility-fixed-01.xcresult`.
- Stale-anchor repro: 38 tests; 36 passed, only the 2 new stale-callback cases failed (5 assertions). The first 17 drill-safety cases, 10 room-entry cases, 5 visibility cases and 4 placement cases passed. Receipt: `/private/tmp/replayxi-physical58-stale-repro-01.xcresult`.
- Final targeted combined run: 56 passed, including all 19 drill-safety, 10 room-entry, 5 visibility and 4 placement cases. Receipt: `/private/tmp/replayxi-parallel62-fixed-01.xcresult`. Source parse and whitespace checks pass.
- Full native suite: 606 passed, 1 optional skip, 0 failed. Device Release build passed. See [batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).

UI wiring checks inspect source; they are not interactive or visual QA. The desktop was locked. Physical anchor placement, headset gesture feel and on-device layout still require an unlocked-device pass.
