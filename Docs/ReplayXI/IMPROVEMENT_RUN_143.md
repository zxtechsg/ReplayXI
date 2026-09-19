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

Native bake releases a populated renderer without an explicit shutdown phase;
that is a plausible lifecycle target, not an established cause. A bounded
physics-bake/stage-only stress test is being prepared before changing shipping
physics. No coverage is skipped to conceal the crash.

Unsigned device Release verification and a clean full-suite retry remain
pending. The Mac is locked; no hands-on headset input or comfort claim is made.
