# Run 156 — copy a tactical pose

Status: full regression passed (1,598 passed, two intentional skips, zero failed), followed by 41 passing final focused tests and a passing unsigned device Release after the feedback-lifetime correction.

## Intent

`Copy pose here` makes a fixed, editable copy of a spatial annotation at the current replay time. It keeps the displayed shape/elevation, gives it a new ID and the normal new-annotation visibility window, and removes tracking/position keys from the copy. The source remains unchanged. Player labels are excluded because they require player identity.

Existing match overlays may be copied without unlocking or deleting them. An explicit copy may sample a source outside its own visibility window: keyed poses hold and tracked poses use current presented player positions. No automatic offset or hidden animation is added.

The action belongs in an ID-bound retractable Actions submenu, replacing the inspector's standalone Erase slot rather than adding a main-bar control. Selection observers must preserve the explicitly selected copy's Adjust panel, without keeping stale panels attached to other marks.

Safety checks: current scenario/source, coach role, drawing/scrub/gesture ownership, dirty timing draft, placement, time, 128-mark limit and geometry validity. Only an accepted copy pauses playback and creates one Undo step. Save/reload and Undo must preserve the source exactly.

## Implementation and review

- Added Store admission/action, ID-bound retractable Actions shelf and narrow insertion/selection observer rules. The new copy opens its own Adjust panel; ordinary drawing and stale selections retain their existing behavior.
- Kept authored MATCH overlays locked. Copy preserves their currently presented pose in a new editable coach mark. Player labels offer Erase only; accessibility hints reflect the available action.
- Added scoped feedback for geometry-rejected copies and the 128-mark limit. Dirty/stale callbacks cannot surface unrelated Store status. No per-frame geometry validation was added.
- New coverage: eight Store tests, four safety/disk tests, eight route tests, three native SwiftUI capture tests and one native scene test. Safety checks include all five reference studies in three views, cross-scenario save/reload, exact source preservation and one-step Undo/Redo.

## Test evidence

First focused run: `/private/tmp/replayxi-cycle156-focused26.xcresult`, 86 passed and one new native test failed. The failed fixture tried to compare two raised arcs while selecting an editable copy. Two seven-draw arcs exceed the existing 13-draw remainder after reserving editable handles, so the hidden source correctly retained its prior geometry. Corrected the test to compare both admitted arcs without selection, then separately check selected-copy stability and hidden-source admission. No renderer or budget change. Reduced repeated vertex assertion output to the maximum point error.

Corrected native test passed: `/private/tmp/replayxi-cycle156-native-fixed26.xcresult`. The source animates and rewinds while the copied mesh, arrow and hit volumes remain fixed in table, first-person and touchline views. This is native graph/mesh integration evidence, not a headset interaction test.

Native default/AX5 Actions screenshots were inspected under `/private/tmp/replayxi-cycle156-focused-captures`: `409B701E-AB2F-4651-966F-83338B164921.png`, `A4BD4A1D-6585-4C9E-820B-8B5DB28532F6.png`, `AF2D3DCB-35F9-4ADA-BABA-5D290B894615.png`. No clipping or overlap. White copy text on the bright tint was weak; changed that action to black text before final verification.

Initial unsigned device Release passed (`cycle156-release.log`); final text-color change is being rebuilt in `cycle156-release-final.log`. Full regression: `cycle156-full26.xcresult`.

Final UI review found that clearing failed-copy feedback on every playhead change would erase it on the next playing frame. Removed that frame-based clear; source-ID scoping, opening/closing Actions, successful copy and semantic review changes still bound its lifetime. Added a wiring regression. This small correction follows the full-suite compilation and needs a final focused run plus `cycle156-release-verified.log`; do not call the earlier full result exact final-binary evidence.

Final verification: `/private/tmp/replayxi-cycle156-final-focused26.xcresult` passed all 41 selected tests on the corrected code; `/private/tmp/replayxi-cycle156-release-verified.log` passed. Full regression before that final one-line observer correction passed 1,598 tests with two existing intentional skips. Final AX5 images `C1F53F2D-5B75-428D-BCED-B678625B1CE5.png` and `956970A3-7C8C-430F-81E4-367B5B9F86A3.png` under `/private/tmp/replayxi-cycle156-final-captures` confirm the dark copy text and readable failure hint without overlap. No hardware gesture, comfort or FPS claim.

## Next bounded checks

- Saved-review Load/Delete confirmations replace the list but omit the target identity. Add name/scenario/time within the existing scrolling confirmation, keeping captured restore and live UUID deletion semantics.
- Measure identical player-label collision-box generation requests before sharing their resource; keep collider bounds, picking and scene output exact. No FPS claim from operation counts.
- Latest run155 native receipt still shows a 25.77° Argentina #10 left-forearm step over 1/120 s near 1.825 s in the rebound study, both detail levels and outside the contact core. Trace stages and shrinking time steps to distinguish a discontinuity from steep continuous motion before changing the rig.

## Previous checkpoint

Run155 committed and pushed: `25b551252806da60bea4668cd72112933227b8a1`. Full visionOS26.5 regression: 1,574 passed, two intentional skips, zero failed. Unsigned device Release passed. Normal latest demo launched on the main27 simulator, PID96407. User review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65` after install/launch. Static launch capture: `/private/tmp/replayxi-cycle155-launched.png`.

No new animation fix was justified by the bounded read-only audit. Current joint-step numbers alone do not prove a visible defect; old pre-integration foot-travel measurements do not establish planted-foot sliding. The earlier intermittent full152 native cleanup crash remains unresolved. Do not treat the clean155 suite as a root-cause fix.
