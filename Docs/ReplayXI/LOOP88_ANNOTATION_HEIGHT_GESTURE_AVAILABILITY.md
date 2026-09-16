# Loop 88 — Height controls and active gestures

## Reproduction

Select a coach-created annotation, open Adjust, then hold the main timeline or an endpoint joystick/direct handle. The adjustment shelf remains visible. For a mark at 1 m, its height buttons only check the 0–4 m limits, so both directions still appear available. The Store rejects those actions while another gesture owns the timeline or geometry. Feedback already respects rejection; this is an availability/hint mismatch, not a saved-data corruption finding.

## Bounded fix

The existing playback-view ownership gate now runs before the height eligibility checks. Unavailable controls give a finish/cancel hint. The Store, owning gesture completion/cancellation and whole-arrow endpoint clamping are unchanged. No new height-edit feature or broad control lock was added.

## Validation

The seven-case `AnnotationElevationGestureAvailabilityTests` class has two source checks for private SwiftUI eligibility/hint wiring and five real Store controls. Those cover scrub, direct-handle and joystick ownership with both commit and cancel, unchanged preview/snapshot/history on rejection, ordinary quarter-metre steps, and partial whole-arrow clamping when one endpoint is at a limit. Stores use memory-only review libraries.

Pre-fix receipt: `/private/tmp/replayxi-parallel88-91-repro-01.xcresult`. Both UI wiring cases failed with three assertions; all five real Store controls passed. All seven post-fix cases passed in `/private/tmp/replayxi-parallel88-91-mixed-02.xcresult`. The production change is limited to the eligibility guard and accessibility hint. Tests and tolerances are unchanged. Source parse and whitespace checks pass. Full suite and Release: pending.

Desktop locked: no interactive button, VoiceOver or headset-QA claim. UI wiring is source-checked; Store transactions run natively under the test host.
