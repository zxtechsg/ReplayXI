# Improvement run 142

Goal remains active. Personal project signing and Info.plist edits stay outside
Git backups. This loop follows the two verified shipping fixes in `aa29b65`.

## Second header: same fix, different contact branch

The City #9 header uses the unconstrained aim branch, unlike France #10's
explicit support-leg header. Two native optimised tests pass on both near and
low-detail skins. No additional production animation changes were needed.

| Window | Chest peak before / after | All-joint peak before / after |
| --- | --- | --- |
| Entry | 23.594° / 4.284° | 23.594° / 7.698° |
| Exit | 35.899° / 3.737° | 35.899° / 7.742° |

The windows use a global 120 Hz grid over ±160 ms. Shrinking to ±10 µs gives
chest differences of 0.040° and 0°, replacing old discontinuities of 23.358° and
36.094°. All 88 positive-action frames and 15 physical-core frames per detail
remain exactly equal to the old-path control. Source poses, bone lengths,
floor clearance and reverse seeking also pass. Remaining measured peaks are
right-toe motion, not evidence of FIFA-level motion or headset comfort.

- `/private/tmp/replayxi-cycle142-native-scenes-optimized.xcresult`
- `/private/tmp/replayxi-cycle142-city-optimized-captures`

## Full-scene measurement: verified baseline

The new test explicitly bakes each of the five native recordings before timing,
then samples tactical, touchline and first-person views in forward, reverse and
paused phases. It includes current near/low skins and articulated far assets.
Timing excludes preparation, assertions, state readback, resource census and
rendering. Separate passes verify repeat/reverse states and load counts.

The first run failed 15 census assertions, one per scene/view. Its old helper
assumed no joint-bearing models outside the near/low skin roots, but current
far-player arms and legs are also articulated. The captured unexpected paths
were checked against the admitted far assets: exactly 88 paths, the two arms
and two legs of all 22 retained players. Each must have precisely the three
admitted joint names and three transforms. The corrected oracle still rejects
missing or unexpected skeletons; it does not simply ignore extra models.

The corrected native optimised run passes. Median update ranges in milliseconds
across the five studies:

| View | Forward/reverse | Paused |
| --- | --- | --- |
| Tactical | 0.357–0.388 | 0.342–0.371 |
| Touchline | 0.353–0.384 | 0.341–0.377 |
| First person | 0.298–0.322 | 0.287–0.314 |

The largest single update was 1.750 ms; the largest per-phase p95 was 1.507 ms,
both in first-person samples. There is no timed performance pass/fail threshold
and no shipping optimisation based on these numbers. This is a fresh CPU-only
baseline, not a before/after speedup, complete frame time or headset FPS.
All five native recordings, repeat/reverse-state checks, shared-mesh limits,
load counts and ordinary detail transitions pass.

- `/private/tmp/replayxi-cycle142-optimized-verified.xcresult` and `.log`
- `/private/tmp/replayxi-cycle142-scenes-verified-captures`

## Annotation event callbacks: current-ID lookup

A retained event chip can contain an old annotation value after retiming or
erasing it. Its action now resolves the current ID and time
before changing transport, selection or overlay visibility. Explicit review
still jumps to In; spatial selection remains a separate pause-in-place action.

Seven regressions cover retiming, visibility-window changes, erased marks and
Undo, previous scenarios, both roles, authored and coach marks, active timeline,
joystick, handle and drawing transactions, and protected timing drafts. The
event chip only changes presentation after an admitted pause and exact seek.
Updated wiring checks preserve the separate event/spatial behaviour.

All 45 focused optimised tests pass, including both City-header regression
guards, event navigation, ownership, timing and accessibility routes. The City
checks now require the measured continuity and reduction against a legacy
negative control, without freezing compiler-specific optimised hashes.

The first full Debug run is not green: result summary reports 1,431 passing
tests, two intentional skips and one SIGSEGV. It attributes the crash to the
new header-stage test, immediately before the next native capture test starts.
The log reports an unknown Objective-C weak-variable unregister; the test
runner restarts, and the retried capture plus remaining assertions pass. Crash
stack/lifetime investigation is required; this is not treated as a harmless
warning or hidden by removing coverage.

- `/private/tmp/replayxi-cycle142-full.xcresult` and `.log`

Cross-review also found the physical tap/recovered-tap path could change
selection before validating a retained annotation target. That routing guard
is being unified with the accessibility path before final validation.

Saved production reviews still match SHA-256
`952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
Device Release verification remains pending.

The Mac remains locked. No hands-on gaze, pinch or headset comfort validation
is claimed.
