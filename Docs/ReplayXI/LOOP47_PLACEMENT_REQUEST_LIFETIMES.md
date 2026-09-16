# Loop 47 — cancel placement without stale results or errors

## Bugs fixed

- Session and placement lifetime checks previously ran only after success.
  A provider failure arriving after Stop, End drill or task cancellation could
  reach a newly opened preflight as a fresh-looking error. Both outcomes now
  pass the same lifetime checks; valid current-provider errors still propagate.
- Failed-add cleanup could itself suspend past a restart. It is now inside the
  placement lifetime gate and is revalidated after cleanup finishes. The cleanup
  still uses the original provider and anchor, never a replacement provider.
- The positioning panel did not retain its request task. Back/reopen or consent
  withdrawal could therefore let an old add finish in a new preflight. Each
  attempt now owns a unique token and a cancellable task. Duplicate taps are
  blocked immediately, before ARKit starts the first operation.
- Back, scenario change, preflight reset, lost confirmation and panel removal
  cancel the attempt. A stale task cannot activate a drill, show an error, or
  clear the handle of a newer request. While old provider work winds down, the
  disabled button says “Finishing…” rather than implying a new add has begun.
- Rejected-result cleanup is scoped to its returned anchor ID. It cannot retire
  a newer local anchor or invalidate that newer placement's intent.

## Verification

- Before the fix, three new regression tests failed against the old helper:
  stale session failure, cancelled-task provider failure, and ended-drill failure.
  `/private/tmp/replayxi-placement47-repro.xcresult`.
- The final suite includes **20 coordinator-lifetime tests** and **4 attempt-token
  tests**. These exercise real async suspension, cancellation during cleanup,
  restart/retirement races, legitimate errors, duplicate requests, ownership,
  cleanup counts and ID-scoped retirement without requiring a physical tracker.
- Full Simulator suite: **458 passed, 1 optional skip, 0 failed (459 total)**.
  `/private/tmp/replayxi-placement47-full-01.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-placement47-release-01.log`.
- Python checks: **108 passed, 12 optional skips**, no failures. A source-level
  guard verifies that the panel uses cancellation, token checks and ID-scoped
  cleanup; it is not a substitute for clicking the UI.
  `/private/tmp/replayxi-placement47-python-01.log`.
- `git diff --check` passed. No changes to signing, provisioning, saved reviews,
  networking or Group Activities capabilities were included.

## Limits and next checks

Actual ARKit placement, hand input and fast native Back/reopen gestures still
need a physical headset and an unlocked desktop. The Mac is locked, so those
interactive checks are not claimed. Background tests verify the async ownership
rules and compiled panel wiring, not hardware tracking quality.

The outer immersive-room exit path still deserves a separate ownership audit:
it removes an anchor asynchronously before stopping tracking, and a rapid room
reopen must not let that old teardown stop a new room. This batch fixes placement
attempts and their cleanup, not every possible room lifecycle race.

The timed goal remains active; this is a verified backup, not the 9am handoff.
