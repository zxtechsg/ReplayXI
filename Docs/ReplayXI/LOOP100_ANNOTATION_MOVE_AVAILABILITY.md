# Loop 100 — Annotation MOVE availability

## Reachable mismatch

In Match Replay or Shape's annotation editor, select a coach-created mark at 5 seconds, then hold the main timeline at 12 seconds. The selected-mark inspector remains present. Its MOVE button checks only time and annotation-window bounds, so it stays enabled and advertises a commit. The Store correctly rejects that competing edit while the scrub owns the playhead. A direct world-handle preview can likewise coexist with the inspector. No mark mutation or false success confirmation occurs; the button offers an unavailable action.

## Baseline extraction and regression

The existing eligibility math was first moved unchanged into `PlaybackAnnotationMovePolicy`, used by the live private UI wrapper. The finite/range checks, 0.05-second difference and `CoachMarkTimingPolicy.windowFits` call were identical. This baseline extraction intentionally retained the missing gesture check for reproduction.

`PlaybackAnnotationMoveAvailabilityTests` has six cases. Three compare the live policy with real Store rejection during timeline, direct-handle and joystick ownership, including normal commit/cancel. Two preserve ordinary Replay/Shape retime + Undo and existing window bounds. One source wiring check covers the private SwiftUI callback, disabled binding and assistive hint; it is not a substitute for rendered interaction.

Pre-fix receipt: `/private/tmp/replayxi-parallel96-99-100-pre-02.xcresult`. The three ownership cases failed six assertions, and the callback/hint case failed three. Both normal/window controls and the existing control-deck clarity tests passed.

The policy now first checks `store.canChangePlaybackView`; the MOVE callback rechecks eligibility before pausing. Its blocked hint asks the wearer to finish or cancel the gesture. The six tests are unchanged. All six pass in `/private/tmp/replayxi-parallel96-101-target-01.xcresult`, along with all 14 control-deck clarity cases. The clean full receipt `/private/tmp/replayxi-parallel96-101-full-01.xcresult` has 837 passed, one optional skip and zero failures (838 total). Unsigned device Release also passed: `/private/tmp/replayxi-parallel96-101-release-01.log`. No Store, timeline/handle ownership or timing-math changes. Swift parse and whitespace checks pass.

Desktop locked: no screenshot, interactive, VoiceOver or headset QA claim.
