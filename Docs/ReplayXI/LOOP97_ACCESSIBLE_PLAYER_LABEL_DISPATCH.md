# Loop 97 — accessible player-label dispatch

## Verified source gap

The normal player tap and short-drag paths call `labelPlayer` when Draw → Label is armed. The accessibility event path instead rejects every drawing state, so an accessible player activation cannot complete the same one-player label action.

The local RealityKit SDK exposes `AccessibilityEvents.Activate(entity:)`. Tests can therefore pass the real event payload and real factory-created body/annotation targets through the app's shared handler. This is not a simulated VoiceOver session or physical-headset evidence.

## Baseline extraction

`PlaybackAccessibilityActivationRouter` preserves the current handler's room and Store transaction gates, annotation-selection callback order, annotation review transport, and normal player-POV dispatch. The baseline extraction deliberately retained the Label no-op before the native pre-fix run. Tap/short-drag paths share the unchanged player-ancestor resolver and annotation-review command. No gesture recognizer, collision, deck layout or saved schema changes.

`PlaybackAccessibilityActivationTests` covers the Label action at 12.25 s, normal/current POV, existing annotation selection/seek order, timeline and endpoint ownership, non-label drafts, held-stroke/end transitions, disabled targets/ancestors, deleted marks, previous-scenario targets, room close/reopen ownership, and runtime callback wiring.

## Pre-fix evidence and scoped repair

Receipt: `/private/tmp/replayxi-parallel96-99-prefx-02.xcresult` and matching `.log`. Six cases passed; six failed with 12 assertions.

- Main defect: two Label cases failed—ordinary armed activation and a fresh activation after stroke ownership ends.
- Separate defensive event probes failed for a disabled target/ancestor, deleted mark, held-stroke annotation and previous-scenario player. These explicitly inject retained events; they do not establish that VoiceOver actually delivers those stale events on hardware.
- The held-stroke case's second failed enablement check was a cascade: the invalid first event selected the preset, so scene focus disabled the new mark's body target. The playhead remained 12.25 s; no fixture condition was relaxed.

The handler now rejects held strokes and disabled/out-of-current-match targets, resolves a still-existing mark before changing selection, and permits only atomic armed Label creation during drawing. Two-point drafts remain untouched. Existing room and Store transaction authority still runs first; no new gesture token or event-deduplication guarantee was invented.

Post-fix targeted receipt: `/private/tmp/replayxi-parallel96-99-postfx-02.xcresult`. All 12 Loop 97 cases pass. Full native receipt: `/private/tmp/replayxi-parallel96-101-full-01.xcresult` has 838 tests, 837 passed, one optional skip and zero failures. Unsigned device Release succeeded in `/private/tmp/replayxi-parallel96-101-release-01.log`. No interactive or headset validation claimed.
