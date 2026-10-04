# Replay XI animation and coaching UI polish

This pass improves the existing local replay. The counterattack and volley are
the first short sequences audited as full 22-player scenes. They remain authored
reconstructions, not recovered body tracking.

## Changes

- Baked a relaxed Tripo recovery run in Blender. It changes arm rotations only.
  Existing lower-body source channels and ball-contact actors are preserved.
  The native scene admits it only for eligible off-ball movement.
- Added four fictional skin palettes across both team kits and keeper kits.
  Geometry and scale stay shared and equal. Faces and hairstyles are still shared;
  these are not athlete likenesses or race assignments. No new Tripo credits spent.
- Added small chest-local clearance so Tripo jersey digits do not clip into folds.
- Split the upper-left HUD into View, Overlays and Room. Only one group expands.
  The workspace stays room-fixed and movable; explicit Recenter moves it once.
- Replaced the immersive source-video popover with an inline Source clip shelf.
  Detailed reconstruction notes retract. The situation header names its source.
- Extracted the HUD from the large immersive view. A load-time channel comparison
  skips redundant blends on unchanged joints. No new per-frame allocation is needed.

The UI follows Apple's guidance on cohesive surfaces, limited movement and large
interaction areas. Buttons retain at least 60-point target height. See
[Apple's spatial interaction session](https://developer.apple.com/videos/play/wwdc2024/10086/).
Source motion also keeps the authored track separate from the in-place gait,
consistent with the distinction described in
[Unity's root-motion guidance](https://docs.unity.com/en-us/engine/6000.6/manual/animation-section/animation-mecanim/avatar-creationand-setup/root-motion).
This is a native RealityKit app; no engine migration was made.

## Evidence so far

- 28 focused native tests passed in `tests08.xcresult`: UI, appearance, decoder,
  source-panel routing and native renders.
- 17 focused tests passed in `tests11.xcresult`: full-scene counterattack and volley,
  source channels, rewind and existing Rocketbox extension regressions.
- The scene audit samples 406 counterattack frames and 316 volley frames at 30 Hz.
  Eligible recovery players on both teams change pose; protected contact actors
  remain exactly equal to the control. Rewind reproduces the same joint transforms.
- After sparse blending, sampled lower-body matrix differences are zero. Minimum
  skin-floor clearance is about 6 mm. This is a geometry check, not a foot-force model.
- Counterattack warm DEBUG Simulator CPU median: control 5.78 ms, new 5.83 ms.
  Volley: control 6.67 ms, new 6.75 ms. These are local samples, not device FPS.
- Native window-layout images cover regular and largest text. Spatial glass is
  omitted from those captures because UIKit cannot snapshot its composite. The
  actual immersive app was also launched and its framebuffer inspected.

Result bundles are under `.codex-derived/replayxi-polish170/`. Earlier failed runs
caught export drift, capture framing and blank spatial-glass snapshots; they are
not counted as passing evidence.

[Scene metrics](Evidence170/counter-scene-audit.json) ·
[Largest text](Evidence170/view-largest-native.png) ·
[Palette preview](Evidence170/home-deep-native.png) ·
[Asset provenance](../../Assets/ReplayXI/TripoFootballer/Blender/Polish170/asset-manifest.json)

## Limits and next checks

The animation is hand-authored, not EAFC-level motion capture. Footage was reviewed
at quarter speed; gaze and unseen bodies remain estimates. More facial and hair
variety needs new player assets. A logged-in Tripo tab was requested; shared-credit
limits still apply. Headset performance and actual pinch ergonomics are unverified.
The Mac lock blocked interactive Simulator checks, not background builds or tests.
User signing/project edits and existing saved reviews are excluded from this backup.
