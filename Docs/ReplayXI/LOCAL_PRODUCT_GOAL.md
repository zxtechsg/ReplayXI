# Local product goal — 16 September 2026

Active goal: a **time-boxed improvement run**, ending at **09:00 Singapore time
on 17 September 2026 (01:00 UTC)**. This replaces the previous token budgets;
the new goal has no token limit. Check the time before each work batch. Stop
starting work at 08:50, save verified work, and hand off by 09:00. A one-time
thread reminder is scheduled for the deadline; it is not a hard process kill.
Finishing this run does not mean the entire product is complete.

This document records the new authorised product scope, superseding historical
multiplayer and head-following requirements.

## Two features

1. **Match Replay:** take an authorised local football clip (target 60 seconds),
   reconstruct its visible play in an editable Blender world, then replay it
   in visionOS with player POV switching, free look and timed 3D annotations.
   Preserve source timestamps and camera cuts. Explicitly distinguish visible,
   estimated and off-camera tracks. Do not claim measured gaze or exact hidden
   positions from a single video. The current bundled world remains synthetic.
2. **Strategy Analysis:** original Blender-built football assets and authored
   situations for demonstrating runs, passes and spacing. Keep the existing
   licensed rigs as a temporary baseline, not evidence that original player
   modelling is complete. Reuse the same timeline/POV/annotation workflow.

## Shared requirements

- Local-only processing and saved reviews. No Group Activities, invites,
  shared anchors, online rooms or remote generation by default.
- 22 identifiable player viewpoints with head-independent free look.
- Time/player-bound annotations, undo, erase, clear and precise joystick edits.
- Room-fixed, comfortable spatial controls. Deliberate recentering only;
  replay time, camera changes and head movement must not move the workspace.
- A simple transport with retractable Views, annotation tools and inspectors.
  Group related controls and avoid overlapping panels at large text sizes.
- Reusable meshes/materials, measured scene/render budgets, and no asset import
  or regeneration during playback. LOD must preserve identity and annotation anchors.
- Simulator regression and visual checks. Do not call device frame rate,
  hand tracking, comfort or provisioning validated without hardware evidence.
- Small verified Git backups, preserving the user's signing/project changes.

## Delivery order and evidence

- [x] Research public reference workflows and record what was observed versus inferred.
- [x] Replace continuous head tracking with a captured workspace origin.
- [x] Add explicit recenter controls and preserve gesture ownership.
- [x] Use Strategy Analysis as the mode label without changing saved IDs.
- [ ] Visually validate both modes, expanded panels and view switching.
- [ ] Refine panel movement, recovery and accessibility on hardware.
- [ ] Build and validate original Blender strategy assets; integrate admitted assets.
  First asset integrated: original 32-panel ball, one mesh/two materials,
  2,592 triangles. Original player/pitch work is still pending.
- [ ] Obtain the selected reference clip and reconstruct the minute in Blender.
- [ ] Integrate the replay tracks/world with verified frame/time mapping.
- [ ] Measure physical-headset performance and fix remaining bottlenecks.

The existing reference-prep and Blender assembly scripts are scaffolding, not
video-to-world reconstruction. See BLENDER_MATCH_WORKFLOW.md and MATCH_REFERENCE_PREP.md.
