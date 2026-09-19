# Improvement run 144 — timestamp nudges and native diagnostics

## Shipping UI change

- Saved-position timing now has large − / + buttons for 0.1-second edits without typing. They change only the draft; Move commits, Reset discards. Repeated nudges produce one undoable edit when applied.
- Nudges preserve six-digit field precision, reject invalid text and replay-edge overflow, and do not seek or autosave drafts.
- The editor now distinguishes malformed input, a time outside the replay, and a time occupied by another position. Valid pending edits explicitly say they are not saved.
- Normal and largest-text native screenshots show the buttons and messages within the panel; the largest-text capture scrolls to the selected-key controls. These are offscreen native renders, not hands-on headset checks.

## Motion investigation — no production change

The two remaining City #9 right-toe peaks are continuous source motion in the tested intervals. Both sample run frames 11–12, which contain 42.033° of source flexion. All nine processing stages preserve the source toe rotations exactly.

| City interval | Toe delta: 1 / 8 / 64 subdivisions | Maximum boot step: 1 / 64 subdivisions |
| --- | --- | --- |
| 3.883333–3.891667 s | 7.697862 / 0.962349 / 0.120355° | 39.283 / 0.627 mm |
| 4.725–4.733333 s | 7.741501 / 0.967864 / 0.121279° | 51.960 / 0.823 mm |

Across source-frame, track, cue and midpoint boundary probes, ±10 µs movement is at most 0.018603° at the toe and 0.128263 mm at the boot. Minimum sampled boot clearance is +4.67146 mm. Tests use actual imported mesh inverse binds and weights with CPU linear-blend skinning, both near/low detail, exact source/legacy/ball and rewind controls. This does not establish absence of stance sliding, GPU appearance, or headset comfort. No toe clamp or source animation change is justified by this discontinuity hypothesis.

## Physics lifetime investigation — DEBUG instrumentation only

A completed rebound bake creates 12 physics worlds: one primary plus 11 nested aim previews. Cancellation at the first preview still creates two previews before returning CancellationError; it leaves no cached recording. A retry creates another 12 worlds and exactly reproduces the completed recording (841 samples, 840 steps, six touches, zero misses).

All 108 weak references across the 27 worlds (world, renderer, root, ball) are nil before and after a queued main-turn checkpoint. Creation sequence IDs distinguish reused renderer addresses. The primary remains alive when its first preview starts.

No retained Swift owner was found. This does **not** observe completion of CoreRE's asynchronous scene teardown or fix the earlier intermittent SIGSEGV. Release behavior is unchanged; the new observer is DEBUG-only. No undocumented shutdown workaround added.

## Validation and receipts

- Focused native run: **50 tests passed**, zero failures.
- `/private/tmp/replayxi-cycle144-focused.xcresult` and `.log`
- UI captures: `/private/tmp/replayxi-cycle144-timing-candidate/`
- Toe receipt: `/private/tmp/replayxi-cycle144-toe-captures/A419EE17-5486-4AB4-A9CA-8B0EDEC55A12.json`
- Ownership receipt: `/private/tmp/replayxi-cycle144-ownership-captures/DCF4212F-299E-4247-AC2A-54A5E07721C1.json`
- Full suite: **1,448 passed, two intentional skips, zero failures** (1,450 total across XCTest and Swift Testing). No runner restart. `/private/tmp/replayxi-cycle144-full.xcresult` and `.log`; about 315 seconds.
- Unsigned device Release build passed: `/private/tmp/replayxi-cycle144-release.log`. Only the existing unused AppIntents metadata warning.
- Normal simulator demo relaunched as PID `66006` and verified alive. Mac remains locked, so no fresh hands-on UI/gaze/gesture or headset-comfort claim.
- User signing/project settings and unrelated files remain excluded. Saved reviews are unchanged before/after testing and normal launch: SHA `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
- Implementation backed up to `origin/main` as `08f433c`; this follow-up records final validation. The broad improvement goal remains active; the earlier CoreRE teardown crash is still unresolved, not reproduced in this cycle.
