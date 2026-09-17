# Movable workspace and Arc controls

## Scope

The former workspace could only return to a once-captured room position using **Place controls here**. It had no direct grab target. The Draw strip had five tools and no curve editor. These are source/wiring observations, not recorded native pre-fix failures.

## Changes

- A broad **Move** grip sits beside the console. Pinch-drag moves the controls, View HUD and Shape attachments together beneath their unchanged room anchor. The pitch, players and camera are not moved. Release keeps the new position; **Place controls here** resets it.
- One cumulative drag baseline avoids feedback drift. Position is bounded to a reachable offset. Room changes, lost ownership or interruption restore the prior placement. Timeline, annotation and drawing ownership block movement; the five attachment surfaces cannot begin an edit while moving.
- **Arc** joins Draw. All six tools use a separate row below the instruction, keeping their existing label/hit sizes rather than shrinking to fit.
- An arc's **Adjust** shelf keeps both endpoint controls and adds **Curve**: sideways bends; upward lifts. The pad and accessible Bend/Lift buttons use quarter-metre steps.
- The curve pad captures one curve and one Store UUID per drag. Preview stays out of saved snapshots, finish commits once, and interruption cancels only its own token. Another pad or stale callback cannot cancel the current owner. Existing Store Undo and geometry limits remain authoritative.

## Checks

The arc is a saved quadratic 3D curve, with independent sideways bend and lift. Both endpoints still support existing player/time binding and height controls. A curve uses one bounded 32×6 tube mesh, not a draw per segment. Invisible hit targets follow its curve rather than filling the straight chord. Unchanged and purely translated player-bound curves reuse their mesh; a bend, endpoint, height or pitch-clipped shape change rebuilds it. This is an allocation policy, not a headset frame-rate claim.

Old review payloads have no curve field and continue to decode. A curve preview is excluded from saved state; release commits one Undo entry, interruption restores the exact prior shape, and closed gesture tokens cannot restart it. Retime, player binding and elevation edits preserve the curve.

- Swift parser and whitespace checks pass.
- Added `PlaybackWorkspaceMoveTests` (10 cases): cumulative movement, finite bounds, blocked/stale ownership, cancellation, unchanged room/pitch transforms, recenter retention, native grab components and gesture wiring.
- Added `AnnotationCurveAdjustmentControllerTests` (10 cases): cumulative baseline, final sample, Undo/snapshot isolation, cancellation, timeline and token contention, stale/duplicate/end-only callbacks, bounded nudges, dead zone and UI wiring. Finish must already own a live preview; a queued callback cannot start a replacement edit after cancellation.
- Extended the existing native Draw font/layout checks to six tools. The zone endpoint-copy assertion now includes Arc; its geometry expectations are unchanged.
- Targeted verification passed **82/82 tests, zero failures** in `/private/tmp/replayxi-player-ball-arc-second-01.xcresult`, including all 10 workspace, all 10 curve-controller and all 8 updated Draw metric cases.
- Final full native verification passed **986 total, 985 passed, zero failures, one optional transient-fixture skip**: `/private/tmp/replayxi-player-ball-arc-full-02.xcresult`. Generic visionOS Release passed with signing disabled: `/private/tmp/replayxi-player-ball-arc-release-01.log`. This is build/test evidence, not an installed headset run.
- Parent's Simulator screenshot review confirms the Move grip, purple Arc tube/arrow, endpoint controls and Bend/Lift pad are visible. At 1296 × 768 the lower shelf reaches the lower edge, without cut labels in that capture. CUA input returned `-10005` / `noWindowsAvailable`; no successful native drag has been demonstrated. No headset comfort or hand-tracking verification has been performed.

Suggested Simulator smoke: move/release the grip and confirm the pitch stays still; reopen a submenu; recenter; draw Arc; adjust bend/lift and endpoints; Undo; attempt Move while scrubbing. Headset testing must separately check gaze acquisition, pinch depth and placement comfort.

## API basis

The targeted drag uses cumulative `translation3D` converted into the stable anchor, with separate collision/input components. See Apple's [entity gesture guidance](https://developer.apple.com/documentation/realitykit/transforming-realitykit-entities-with-gestures), [3D drag translation](https://developer.apple.com/documentation/swiftui/draggesture/value/translation3d) and [InputTargetComponent](https://developer.apple.com/documentation/realitykit/inputtargetcomponent). Local SDK declarations were checked; no head-follow anchor was introduced.
