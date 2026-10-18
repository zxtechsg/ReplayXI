# Playback editing checkpoint 181

## Changes

- Room-fixed playback cards face the viewer via RealityKit `BillboardComponent`.
  Their room anchor and pinch-drag movement are unchanged. No eye data is read.
- Follow controls can link the origin, end, or both points. Each end can follow
  a different player. Linking/unlinking keeps the displayed offset, is undoable,
  and persists in the existing review format.
- Mac has a local 3D tactical editor, with orbit/zoom, player POV, framing the
  selected mark, draggable endpoints, an arc control point, and Shift-drag height.
  This uses live replay positions; it is not a second physics simulation or a
  copy of the headset's detailed character renderer. 2D editing remains available.
- Each annotation gets a timeline lane. Clip ends trim visibility. Diamonds
  jump to poses; previous/next buttons do not wrap.
- With Record moves on, seeking and moving a point saves its pose atomically.
  The first move preserves the original pose at the mark's reveal time. Existing
  poses remain editable, removable, and retimable. Freeze here is explicit and
  undoable. Player-follow and saved-pose motion are still separate modes.
- Scrubbing coalesces to eight previews/sec. Release sends the exact final time;
  other transport actions cancel queued previews. PIN, revision, scenario, and
  paused-edit checks remain enforced.
- Tripo hands use each rig's bind palm plane and thumb side, with varied relaxed
  fingers and a bounded wrist rotation. Explicit save/parry wrist IK is kept.
  The Rocketbox rig, arm lengths, root, boot and head solvers are untouched.

## Evidence and limits

- `replayxi-viewer-facing180.xcresult`: 36 passed.
- `replayxi-editing-hands181.xcresult`: 34 passed, no skips/failures.
- `replayxi-hand181b.xcresult`: 17 passed, including arm, upper-body and parry
  regression checks. A later palm-side correction still needs visual review.
- `replayxi-mac-editing181c.xcresult`: 32 passed. Native SceneKit render was
  inspected: pitch, both teams, numbers, curved mark and control handles visible.
- Mac layout fixture images are not proof of compositor/glass rendering:
  `ImageRenderer` cannot capture AppKit/SceneKit/inspector layers correctly.
- Final expanded runs were interrupted after they stalled while the Mac was
  locked. They are not passing results. Rerun after unlocking, including the
  latest palm-side change and projection-coordinate test. Headset hand gestures
  and physical comfort still need device testing.
- The official Argentina–France source was rechecked at video 36:56. It supports
  strike-balance/running posture, but fingers are too small for exact pose recovery.
  Hand changes are anatomical polish, not measured video mocap or EAFC fidelity.
- No new asset service credits were spent. No rejected stadium was integrated.

Primary API references: [BillboardComponent](https://developer.apple.com/documentation/realitykit/billboardcomponent),
[SCNTorus axes](https://developer.apple.com/documentation/scenekit/scntorus),
[view-space unprojection](https://developer.apple.com/documentation/scenekit/scnscenerenderer/unprojectpoint(_:)).
Match reference: [FIFA broadcast, 36:52 onwards](https://www.youtube.com/watch?v=RgqKdplLIk4&t=2212s).
