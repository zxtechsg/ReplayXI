# Verified batch — loops 66–73

Verified at approximately 04:12 SGT on 17 September 2026.

## Scope

- Ball rolling follows replay travel and stops on stationary segments.
- Discrete timeline controls cannot interfere with an owned scrub gesture.
- Shape comparison preserves in-progress annotations.
- One football-action sample per player replaces duplicate calculations.
- Review-sized player tags clear heads without following head animation.
- Larger secondary text controls and an accessible playback-speed grid.
- Correct impact boot rest bases and smooth procedural neck neutral blend.
- Workspace presets cannot move controls during an active gesture.

## Results

- Native Debug suite: **657 total; 656 passed, 1 optional skip, 0 failed**.
  `/private/tmp/replayxi-parallel73-full-03.xcresult`
- Unsigned physical-device Release build: **passed**.
  `/private/tmp/replayxi-parallel73-release-01.log`
- Python checks: **126 total; 114 passed, 12 optional skips, 0 failed**.
  `/private/tmp/replayxi-parallel73-python-01.log`
- `git diff --check`: **passed**.

Native counts include two Swift Testing cases. Earlier attempts caught a test-only
UIKit font-style typo and a stale source-string assertion; both were corrected
before the clean final full run. Individual loop notes retain pre-fix evidence.

Loop 72 includes eight inspected before/after Blender renders from native pose
exports. All sampled full meshes clear the turf; the smallest after clearance is
5.388 mm. This is sampled evidence, not a guarantee for all animation frames.

## Limits and preservation

The desktop is locked; no interactive Simulator or headset QA is claimed. Native
font metrics are not a rendered SwiftUI layout check. Reduced work counts are not
a measured headset frame-rate improvement. The demo remains explicitly synthetic,
not reconstructed video. Local-only operation and saved formats remain intact.
User signing/project and Info.plist edits, unrelated files and derived renders are
excluded from the scoped Git backup.
