# Improvement run 143

Goal remains active. This follows the animation/event fixes and scene baseline
in runs 141–142. Personal signing and Info.plist changes remain excluded.

## Validate spatial targets before changing selection

Physical tap and recovered short-drag selection previously assigned the selected
annotation before finding out that a retained target was deleted or drawing was
active. That could dismiss tool panels even though transport rejected the hit.

Both physical paths and accessibility activation now share target admission:
current room, current match, enabled hierarchy, real annotation target, current
saved mark, and no drawing, held stroke, timeline or geometry owner. Rejected
annotation hits are consumed instead of falling through as player/pitch taps.
Only an admitted hit invokes the selection closure. Static reveal review,
animated pause-in-place and player-local comfort review are preserved.

Five added native regressions exercise the shared physical and accessibility
paths with deleted, drawing, held, hidden, disabled, retired-room, old-scene,
timeline and geometry-owner targets. Source checks ensure both view callbacks
delegate admission and cannot assign selection early. Existing role and
selection-before-review behaviour is retained.

All 47 focused Debug tests pass:
`/private/tmp/replayxi-cycle143-target-admission.xcresult` and `.log`.

## Scene-teardown investigation

The failed full run's stack traverses `RealityRenderer.deinit`, scene removal
and physics-simulation destruction before the Objective-C weak-reference fault.
The same signature predates the header change (cycle131). The new capture
helper's explicit camera/resource lifetime matches the established cut tests.
Neither fact identifies the particular renderer or proves an SDK defect.

Root inspection confirms the same leading 27 stack frames in:
`/Users/zx/Library/Logs/DiagnosticReports/ReplayXI-2026-09-20-043652.ips` and
`/Users/zx/Library/Logs/DiagnosticReports/ReplayXI-2026-09-18-163724.ips`.

Native bake releases a populated renderer without an explicit shutdown phase;
that is a plausible lifecycle target, not an established cause. A bounded
physics-bake/stage-only stress test is being prepared before changing shipping
physics. No coverage is skipped to conceal the crash.

The isolated stress baseline now passes: 12 fresh bakes cycle all five studies,
checking exact full sample/touch digests against each study's first bake, zero
missed contacts, both teams at near/low detail, all nine observed motion stages,
exact reverse seeks and release of the test-owned skin instances. A queued main
turn and task yield follow each iteration. No camera/capture renderer is made.
The private physics renderer's identity and completed teardown are not observed;
this pass does not establish a cause or prove the earlier crash fixed. Shipping
physics is unchanged. An initial test-only expression exceeded Swift's type-
checker budget; splitting the typed timestamp list preserved its sample values.

- `/private/tmp/replayxi-cycle143-teardown-stress-02.xcresult` and `.log`
- `/private/tmp/replayxi-cycle143-teardown-stress-captures/6BADE426-720B-40A0-80C7-08445ADCDBDD.json`

Unsigned device Release succeeds:
`/private/tmp/replayxi-cycle143-release.log` (only unused AppIntents metadata
warning).

## Final checkpoint

The full retry is green with no test-runner restart: 1,438 XCTest executions,
two intentional skips, zero failures, plus both Swift Testing asset cases pass.
The combined result summary is 1,438 passed / two skipped / zero failed. The
run includes the complete five-scene baseline, all header/annotation tests and
the 12-iteration lifecycle stress check; no failure-prone test was removed.

- `/private/tmp/replayxi-cycle143-full-retry.xcresult` and `.log`

This clean retry does not explain or fix the earlier intermittent teardown
crash. Its saved evidence remains an open investigation item.

Normal demo launch succeeds (PID 64331), verified alive after 12 seconds.
Production reviews are byte-identical, SHA-256
`952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
The Mac is locked; no hands-on headset input or comfort claim is made.
