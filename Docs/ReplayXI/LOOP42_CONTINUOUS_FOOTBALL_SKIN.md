# Loop 42 — keep the player skin through football actions

## Change

- Near players no longer change from the textured body to a segmented body
  when walking, cutting or touching/passing the ball. Impacts still use the
  separately tested procedural ragdoll; no new impact retargeting is claimed.
- A small model-space retargeter maps the existing authored football legs to
  the licensed 80-joint skeleton. It compensates for Biped's thighs being
  children of Spine, preserves bone lengths and grounds the actual sole anchors.
- Procedural side IDs and the source's anatomical joint names have opposite
  X conventions. The mapping uses the rest hip position, so the boot on the
  ball's side receives the strike instead of its opposite.
- Walking and turn weights are continuous telemetry functions. A classifier
  boundary cannot swap bodies or suddenly replace a pose. Contact edges blend
  into/out of the base clip. Slow walking retains more of the idle upper body.
- Jerseys follow the same chest transform; head/neck compensation is retained.
  Arbitrary seeks and reverse playback remain deterministic. Pose arrays are
  reused and the existing near-player/mesh/material limits are unchanged.
- The renderer passes its already-sampled contact pose to the new skin layer;
  it does not scan the ball track a second time for that layer.

## Checks

- Focused motion/skin/contact tests: **23 passed**, no skips/failures.
  `/private/tmp/replayxi-rig42-targeted-02.xcresult`.
- Full Simulator suite after the extra transition/storage checks:
  **406 passed, 1 optional skip, 0 failed (407 total)**.
  `/private/tmp/replayxi-rig42-full-01.xcresult`.
- Unsigned visionOS Release build passed:
  `/private/tmp/replayxi-rig42-release-01.log`.
- Python pipeline checks: **107 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-rig42-python-01.log`.
- Tests cover real asset admission, skin persistence, grounded sole anchors,
  constant leg lengths, continuous walk/jog/sprint/cut boundaries, correct
  striking side, action-window edges, exact rewind, number anchors, buffer
  reuse, LOD limits and wearer hiding.
- Eight actual Swift-runtime poses were exported as an XCTest attachment and
  applied to the existing audited Blender library. Walk, both cuts, pass
  preparation/contact/release and base run were rendered. Front/three-quarter
  inspection showed connected textured limbs, restrained support poses and
  no body replacement. Blender's body-surface minimum ranged from -12.8 mm to
  +0.7 mm at these samples; sole-centre grounding is not full shoe-mesh IK.
  `.codex-derived/ReplayXI-FootballPose42-v1/` contains images and the report.
  `Scripts/blender/render_runtime_player_poses.py` reproduces the check from
  runtime attachments without writing over the player library.
- The app installed and launched in Simulator. Direct desktop click testing
  was unavailable because the Mac was locked; no interaction test is claimed.

An initial test helper referred to the classifier on the state enum rather
than the sample type. It was corrected before successful verification.

## Limits

The model is still the licensed Rocketbox baseline. These are authored motion
adaptations, not football motion capture or FIFA assets. Exact ball/boot contact,
full shoe support, physical-headset frame timing and hand interaction still
need further work. The match demo remains synthetic, not reconstructed footage.

The timed goal remains active; this is a verified batch, not the 9am handoff.
