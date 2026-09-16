# Loop 39 — intentional local pitch retirement

- Ending a drill invalidates any unfinished placement even when no anchor ID
  has arrived yet. A new explicit placement can still run in the same session.
- Explicit removal clears app ownership before the asynchronous ARKit removal,
  so the ensuing removal event is ignored rather than treated as tracking loss.
- Cancellation while replacing a prior origin cleans up the new origin too.
- Delayed cancellation/errors cannot reopen placement errors in a closed view.
- Added three regressions for retirement, a genuinely suspended placement and
  local anchor state cleanup. No physical ARKit tracking was simulated or claimed.

Initial and final targeted simulator runs: 13 tests passed each. Final result:
`/private/tmp/replayxi-local39-retirement-tests.xcresult`.
Full verification follows alongside the next graphics batch. User signing edits
remain untouched.
