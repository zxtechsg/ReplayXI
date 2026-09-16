# Loop 48 — room-owned tracking and safe reopen

## Fixed

- A disappearing room previously removed an anchor asynchronously, then stopped
  whichever tracking session was current. A new room could reuse that session
  while the old cleanup was suspended, only to have tracking stopped underneath it.
- Each immersive view now owns a distinct tracking token. Retirement captures its
  owner and request revision synchronously. A new owner, a returning positioning
  mode, or a restarted session defeats the old pending stop.
- Anchor retirement clears app ownership immediately and removes the exact
  captured anchor through its original provider. Store retirement callbacks now
  use their supplied anchor ID instead of deferring an unscoped removal.
- Provider startup is a coordinator-owned task. A returning room waits for the
  same startup; cancelling the old view's waiter does not cancel the provider.
  Explicit session shutdown still cancels startup and invalidates late results.
- Physical placement remains disabled with “Finishing…” while anchor removal is
  active. An unsupported tracking message is no longer overwritten by selecting
  an empty anchor immediately after startup fails.
- Exit waits for its owned anchor cleanup while the immersive space is still
  presented. A late disappearance cannot stop another room's tracking.

## Verification

- Added **13 ownership/startup tests**: synchronous retirement, wrong-owner no-op,
  repeated exits, rapid reopen, same-view scenario return, cancelled waiters,
  shared startup, delayed old errors, and final unclaimed shutdown.
- Final full Simulator suite: **471 passed, 1 optional skip, 0 failed (472 total)**.
  `/private/tmp/replayxi-room48-full-02.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-room48-release-02.log`.
- Python checks: **109 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-room48-python-02.log`.
- Source guards check token-scoped view teardown, exact-ID Store callbacks,
  shared startup waits and the removal-state button gate. These are not UI clicks.
- `git diff --check` passed. User provisioning edits and saved reviews were not
  included or overwritten. No network/group capability was added.

## API reference and limits

Apple documents that [`ARKitSession.stop()`](https://developer.apple.com/documentation/arkit/arkitsession/stop())
stops all of that session's providers. Its [`run(_:)` documentation](https://developer.apple.com/documentation/arkit/arkitsession/run(_:))
also rejects already-stopped providers and providers owned by another session.
The fix reuses a still-running session only when a new room explicitly claims it;
once stopped, normal startup creates fresh session/provider instances.

Tests exercise deterministic ownership and suspension rules without live ARKit.
Physical placement and native gesture checks still need a headset and an unlocked
desktop; the locked Mac prevented interactive UI validation. No headset frame-rate
or tracking-quality claim is made.

The room's separate presentation flags still need an audit for repeated Exit taps
and late open/dismiss completions. This batch fixes tracking/anchor ownership, not
every presentation-state race. The timed goal remains active until 9am SGT.
