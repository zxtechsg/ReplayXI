# Loop 124 — explain retained marks in Timeline

The scene deliberately limits simultaneous annotation geometry. Selecting a mark reserves room for its handles and prioritises that mark; others can disappear from the scene while remaining in review history. Timeline previously gave page/event counts but no explanation. This is a clarity gap, not data loss.

Match replay's Timeline now adds only: “Marks may be hidden. Select one here to show it.” It appears only for `.realWorldReplay` when the existing cached `orderedReviewMarks.count > 1`. No live visible-count calculation, render-budget changes, new setting, base-control text or selection behavior change. The existing Timeline row, event counts and paging are preserved.

The hint sits below the row, uses unscaled caption text and wraps at intrinsic height. The shelf, deck and `coach-console` attachment have no fixed height; existing horizontal button space is untouched. No layout-file change was needed. Shape has no explicit old Timeline-height budget, but its separate station panel's fixed spatial offsets cannot be visually checked while locked. The hint therefore stays out of Shape and other Strategy exercises. This is a source/layout check, not a visual or comfort pass.

Three new `PlaybackTimelineVisibilityHintTests` check cached-count wiring, unchanged row/intrinsic-height constraints, and native caption measurements at 12 text sizes × 3 presets. UIKit text bounds are not SwiftUI-rendered attachment bounds. Selected-first behavior reuses `PlaybackAnnotationEligibilityTests.testVisibleSelectionStillHasPriorityWithinTheExistingEnvelope` and the actual scene checks in `PlaybackSceneBudgetTests`; it is not duplicated.

Syntax parsing and diff checks passed. Final integrated suite: 920 passed,
one optional skip, zero failures, including all three new hint cases.
Unsigned device Release passed. See the
[final batch receipt](VERIFIED_BATCH_122_124_2026-09-17.md).
No interactive/headset QA while the Mac is locked.
