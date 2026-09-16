# Loop 55 — Room entry and active gestures

## Reproduced fault

Playing at 5 seconds, previewing a timeline drag at 12 seconds, then entering the room left the scrub transaction alive. When the dashboard slider disappeared, cancellation restored playback at 5 seconds inside the new room. Entry had acquired its presentation request before its pause was rejected by the active gesture.

A clean successful opening also retained `Opening spatial replay…` as its status. Normal system dismissal already paused correctly and reported that the replay was outside the room.

The pre-fix room-entry subset had **9 tests: 5 expected test failures, covering 14 failed assertions, and 4 passing controls**. Receipt: `/private/tmp/replayxi-boundaries55-repro-01.xcresult` (also contains other boundary tests). These failures documented the old behavior; they are not current regressions.

## Fix

- Reject entry during an owned timeline, endpoint or direct geometry adjustment, before acquiring room ownership. Preserve its preview and checkpoint so the user can finish or cancel normally.
- Keep paused drawing drafts valid across entry. Do not discard their first point, change their time or trap the dashboard debug draft.
- Replace preparation/opening text with `Spatial replay ready` only on an accepted current-request success and only if no newer message has replaced it. Stale completions and system dismissal retain their status.
- Apply the same gesture gate and hint to Enter, the Shape Focus Physical step and Open physical setup.
- Disable dashboard input while opening/closing. Normal already-open room interactions remain available.

## Verification

- All **10 `ReplayRoomEntryTests` passed**, including draft carry, stale/duplicate callbacks, newer-message preservation and the three entry routes’ source wiring.
- Combined Simulator suite: **556 passed, 1 optional skip, 0 failed** (557 total). Receipt: `/private/tmp/replayxi-parallel55-full-01.xcresult`.
- Python checks: **111 passed, 12 optional skips**. Swift parsing and scoped diff checks passed.
- Unsigned physical-device Release: **BUILD SUCCEEDED**. Receipt: `/private/tmp/replayxi-parallel55-release-01.log`.

The desktop remained locked. The reproduction used the real domain code; regression tests ran in Simulator. UI gates were checked in source, not by interactive clicking, hand tracking or headset testing.
