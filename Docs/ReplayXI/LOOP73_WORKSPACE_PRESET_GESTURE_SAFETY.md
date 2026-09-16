# Loop 73 — Workspace presets during gestures

## Issue and fix

Source sequence: open Settings, hold the main timeline pinch, then choose a workspace preset with the other hand. Preset buttons remained enabled and wrote the stored preset. That changes attachment position/scale while the timeline owns input. **Place controls here** already rejected this state, but preset selection did not.

Preset availability and its callback now use the same existing placement policy. The callback checks before changing the saved preference. The guard covers a drawing draft, active pinch stroke, timeline scrub and geometry preview; the hint explains why movement is blocked. The normal preset action resumes after the gesture ends. No Store-wide lock or save format changed.

The held-scrub path is reachable from the visible Settings shelf. A simultaneous Settings/geometry path was not proven and is not claimed; geometry uses the same defensive policy for consistency.

## Validation

- Pre-fix receipt: `/private/tmp/replayxi-parallel72-73-repro-01.xcresult`. Loop73 had 2 expected source-wiring failures with 3 assertions; the real Store scrub-owner control passed.
- Callback-before-mutation and disabled-state wiring are source checks. The Store test confirms the actual scrub remains owned and can commit, not a synthetic UI execution.
- Source parse and whitespace checks pass.
- Final full native suite: `/private/tmp/replayxi-parallel73-full-03.xcresult` — 657 total, 656 passed, 1 optional skip, 0 failed.
- Unsigned physical-device Release: `/private/tmp/replayxi-parallel73-release-01.log` — `BUILD SUCCEEDED`.

No interactive headset or visual pass was possible while the desktop was locked.
