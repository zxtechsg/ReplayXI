# Improvement run 145 — ready arms, POV clarity and cancellation

## Player movement

Native near/low skins were applying their relaxed idle arms after football-ready retargeting. This could erase a nearby defender's prepared stance, while the far/procedural path applied readiness after idle variation.

The native idle-arm overwrite now fades out with already-retargeted readiness. Contact protection, keepers and the far path keep their prior behavior. No routes, source clips, root movement, feet, pitch, ball or assets changed.

Measured actual cases (near and low agree):

| Case | Elbow bend before | Elbow bend after |
| --- | --- | --- |
| City overlap, Liverpool #4, 6.0 s | 21.323° / 17.196° | 24.064° / 24.064° |
| City underlap, Liverpool #5, 5.9 s | 19.392° / 17.566° | 22.504° / 22.030° |

All 270 sampled contact-phase comparisons are exact to the pre-fix control (27 contacts × two skins × five phases). Source, root/feet, ball and rewind checks pass. The added arm correction changes by at most 0.889° per 120 Hz step across the tested readiness transitions. Eight matched native images were inspected: a modest visible restoration of prepared arms, without a new mesh break. This is procedural intent, not recovered match mocap or EA FC-level fidelity. Lower readiness does not imply universally more bent arms; the fix preserves the existing retargeted pose.

## POV controls

- View buttons now enter first person paused at the current instant, matching roster/pitch selection. Rate and timestamp are unchanged. Re-selecting the current camera is a no-op; spectator-to-spectator playback continues.
- Existing drawing, scrub and placement barriers remain. Legacy shared-follow state stays unchanged when re-selecting its current view.
- Compact POV labels and roster pills now include team codes: ARG, FRA, MCI, LIV (HOME/AWAY for practice). Same-number opponents are distinct. Accessibility labels include full team, player name, number and role.
- Labels fit the unchanged width budgets at all 12 text sizes. Native captures of the actual controls show both #10s and their full largest-text rosters without clipping. The test host omits spatial glass, not the control layout; it does not test headset reach or comfort.

## Cancelled preparation

The native bake checked cancellation before yielding, but not after resuming. A scenario/view task cancelled at that boundary could still execute another 60 physics steps and create two aim-preview worlds.

A post-yield cancellation check now stops that work. The deterministic regression measures zero subsequent steps and zero preview worlds, an empty cancelled cache, then an exact retry (841 samples, 840 steps, six touches, zero misses). Normal yield cadence and physics math are unchanged. This is not a measured FPS gain or a fix for the separate intermittent CoreRE teardown crash.

## Evidence

- Pre-fix run: `/private/tmp/replayxi-cycle145-baseline.xcresult`. Three test methods failed as expected: 20 live POV-entry cases, current-view follow mutation, and cancelled extra work. Off-ball native inventory passed and confirmed the overwrite.
- Candidate: `/private/tmp/replayxi-cycle145-candidate.xcresult`: **41 passed**. Its first UIKit console images were blank despite the test passing, so those images are **not** UI evidence.
- Corrected UI run: `/private/tmp/replayxi-cycle145-pov-render-03.xcresult`: **22 passed**. Added a bright-pixel gate to reject empty snapshots and isolated the real controls from the spatial glass compositor. Intermediate test-host builds failed due to a private stored flag making the synthesized initializer inaccessible; fixed without adding AnyView/type erasure to the app.
- Verified UI images: `/private/tmp/replayxi-cycle145-pov-captures-verified/`.
- Arm images/metrics: `/private/tmp/replayxi-cycle145-readyarm-captures/` and `/private/tmp/replayxi-cycle145-offball-candidate/`.
- Cancellation receipt: `/private/tmp/replayxi-cycle145-cancellation-candidate/EE1F8B72-A55C-42BB-836F-8DDE1FC29E06.json`.
- Full suite, device Release, final saved-review check and demo relaunch pending at this checkpoint. User signing/project changes and unrelated files are excluded from Git.
