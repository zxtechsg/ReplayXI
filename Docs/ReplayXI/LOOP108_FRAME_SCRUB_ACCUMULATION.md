# Loop 108 — slow frame scrubbing

The immersive timeline rounded every incremental pinch sample to a 30 Hz frame. That discarded sub-frame travel, so many small moves could leave the playhead stuck. Slightly larger samples could round forward repeatedly and overshoot the same single continuous drag. The outcome depended on hand-sample cadence, not just travel.

`PlaybackTimelineScrub.GestureState` now retains an unrounded time accumulator. Frame mode quantises only the displayed time. Leaving frame mode rebases to the visible frame; moving vertically alone never exposes a hidden fraction or shifts the playhead. Pitch/annotation logic and the store-owned scrub transaction are unchanged. The fix adds one `Double` to gesture state and no per-frame allocation.

The regression varies one 40-point drag across one, eight, 40 and 160 samples, in both directions. It also covers slow reversal, invalid rail geometry, end-of-replay overshoot and precision transitions. The actual SwiftUI handler retains this gesture state across drag updates and uses its displayed time for both preview and commit.

## Receipts

- Before: `/private/tmp/replayxi-timeline108-before-01.xcresult` — six new cases; three failed with eight assertions. Fine-grained movement stuck at 10 seconds, while eight larger samples overshot by three frames.
- After: `/private/tmp/replayxi-timeline108-after-01.xcresult` — all six new cases and nine existing timeline cases passed (15 total).
- An independent read-only review found no concrete regression. It also checked that the final repeated drag sample cannot apply travel twice and that only displayed time is committed.
- No physical hand-tracking or interactive UI check is claimed; these are deterministic native mapping/store tests. Full-suite verification follows before the next app backup.
