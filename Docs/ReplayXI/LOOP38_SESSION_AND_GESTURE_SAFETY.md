# Loop 38 — session and gesture safety

## Scope and deadline

Local-only Match Replay and Strategy Analysis. Run cutoff: 17 September 2026,
09:00 Asia/Singapore (01:00 UTC). Stop new work by 08:50. The goal service now
holds this time-based goal without a token budget. The existing paused replay
automation was updated to a one-time stop reminder for that date.

## Changes

- A tracking-session revision rejects delayed ARKit startup/placement results
  after stop/restart. Old cleanup cannot clear a new session's placement flag
  or removal task. Placement is rejected while an anchor removal is outstanding.
- Cancellation is checked before and after awaited provider work. Rejected
  placements attempt cleanup on their original provider.
- One camera-change policy protects unfinished drawings, timeline scrubs and
  geometry edits. The Views panel and player controls reflect that policy.
- Updated the earlier product-goal note, retaining the two-feature local scope.

## Validation

- Initial targeted simulator run: 10 tests passed (session lifetime + local
  experience). Session tests use controlled asynchronous operations; they do
  not claim that physical-headset ARKit relocalisation was tested.
- Local-only capability/source checks: 5 passed.
- First full run found one older test expecting a camera broadcast while
  drawing was still active. The test now ends drawing before checking broadcast
  behaviour. New tests separately assert rejection while drawing remains active.
- Final full simulator rerun succeeded: 392 XCTest cases (one optional transient
  asset fixture skipped, zero failures), plus both Swift Testing asset tests.
  Result: `/private/tmp/replayxi-local38-verified-tests.xcresult`.
  Result-bundle summary: **393 passed, 1 skipped, 0 failed**.
  The initial failed run was stopped during Xcode's post-test diagnostics;
  the verified rerun disabled verbose failure diagnostics, not tests.
- Unsigned physical-device Release build succeeded
  (`/private/tmp/replayxi-local38-release.log`). This checks compilation,
  not personal-team signing or on-headset behaviour.

## Next audit candidates

- Explicit anchor retirement can occur while addAnchor is pending. Check that
  this intent invalidates placement even without stopping world tracking.
- Explicit removal currently clears selection after awaiting the provider;
  check that ARKit removal callbacks cannot be misread as unexpected loss.
- Camera/POV-only changes already schedule autosave through property observers
  in PlaybackStore. No extra scheduling fix is needed; a dedicated isolated
  disk-reload regression would still be useful.

No new reference footage, original human model or physical performance claim
was added. User signing and Info.plist changes remain outside our backup commit.
