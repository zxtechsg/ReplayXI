# Replay XI animation and coaching UI polish

This pass improves the existing local replay. All five short sequences are
audited as full 22-player scenes: counterattack, volley, header, cutback and
rebound. They remain authored reconstructions, not recovered body tracking.

## Changes

- Baked a relaxed Tripo recovery run in Blender. It changes arm rotations only.
  Existing lower-body source channels and ball-contact actors are preserved.
  The native scene admits it only for eligible off-ball movement.
  Native A/B review caught overly straight elbows in candidate one; candidate
  two reduces that idle blend and keeps more running bend.
- Added four fictional skin palettes across both team kits and keeper kits.
  Geometry and scale stay shared and equal. Faces and hairstyles are still shared;
  these are not athlete likenesses or race assignments. No new Tripo credits spent.
  Their slot order now follows the existing distant-player tone order. Shader and
  mesh differences between detail levels remain; this does not eliminate LOD changes.
- Added small chest-local clearance so Tripo jersey digits do not clip into folds.
- Split the upper-left HUD into View, Overlays and Room. Only one group expands.
  The workspace stays room-fixed and movable; explicit Recenter moves it once.
- Replaced the immersive source-video popover with an inline Source clip shelf.
  Detailed reconstruction notes retract. The situation header names its source.
- Extracted the HUD from the large immersive view. A load-time channel comparison
  skips redundant blends on unchanged joints. No new per-frame allocation is needed.
- Shared one verified texture loader across base and optional kits. Base texture
  accounting includes the palettes; DEBUG counters check warm asset/texture work.
- Increased the dashboard source button to a 60-point target with hover feedback.
  Free-look guidance calls facing authored, not recorded gaze.
- Native review found clipped Marks/Lanes labels at the largest text size. Overlay
  controls now stack at accessibility sizes, keeping full labels and hit areas.

The UI follows Apple's guidance on cohesive surfaces, limited movement and large
interaction areas. Buttons retain at least 60-point target height. See
[Apple's spatial interaction session](https://developer.apple.com/videos/play/wwdc2024/10086/).
Source motion also keeps the authored track separate from the in-place gait,
consistent with the distinction described in
[Unity's root-motion guidance](https://docs.unity.com/en-us/engine/6000.6/manual/animation-section/animation-mecanim/avatar-creationand-setup/root-motion).
This is a native RealityKit app; no engine migration was made.

## Validation

- 28 focused native tests passed in `tests08.xcresult`: UI, appearance, decoder,
  source-panel routing and native renders.
- 17 focused tests passed in `tests11.xcresult`: full-scene counterattack and volley,
  source channels, rewind and existing Rocketbox extension regressions.
- Three more full-scene audits passed in `tests12.xcresult`: header, cutback and rebound.
- 28 focused tests passed in `tests14.xcresult`: loop seams, jersey attachments,
  scene routing, source links and native HUD layouts. Historical assertions were
  updated to cover the shared update helper and the intentional number clearance.
- The scene audit samples 406 counterattack frames and 316 volley frames at 30 Hz.
  Eligible recovery players on both teams change pose; protected contact actors
  remain exactly equal to the control. Rewind reproduces the same joint transforms.
- After sparse blending, sampled lower-body matrix differences are zero. Minimum
  skin-floor clearance is about 6 mm. This is a geometry check, not a foot-force model.
- Final focused `tests24.xcresult`: **475 passed, zero failed, zero skipped**.
  This includes all five scene audits, native assets, UI and annotation regressions.
- Final unsigned Release builds passed for visionOS device and Simulator.
  All nine optional palettes decode to the expected runtime pixel hashes in both
  packaged Release apps. Their recovery payload hashes also match the source.
  [Device palettes](Evidence170/release-device-pixel-hashes.txt) ·
  [Simulator palettes](Evidence170/release-simulator-pixel-hashes.txt).
- Counterattack warm DEBUG Simulator CPU median: control 5.941 ms, new 5.992 ms.
  Volley: control 6.796 ms, new 6.909 ms. These are local samples, not device FPS
  or evidence of a timing gain. All five warm scene audits record zero native asset
  loads and zero texture preparations in their update loop.
- Loaded base texture data totals 84 MiB with all palettes. This excludes mipmaps,
  staging data and other memory. Invalid optional palettes fall back as a whole kit;
  corrupt optional motion also falls back without removing the base athlete.
- Recovery fades below 0.02 can produce indistinguishable poses. The pose-change
  assertion uses meaningful blends; protected contact and lower-body checks still
  cover every sampled frame.
- Native window-layout images cover regular and largest text. Spatial glass is
  omitted from those captures because UIKit cannot snapshot its composite. The
  actual immersive app was also launched and its framebuffer inspected.
- A fixed-camera A/B gait preview uses 24 native renders per variant, displayed
  at about quarter speed. Left is the original gait; right is the relaxed recovery
  arms. There is no optical-flow interpolation or recovered match/body-motion claim.
- Full `tests15.xcresult`: 1,726 passed, five failed, two skipped. All five
  failures reproduce on the untouched pre-pass commit `6c64be5` with the same
  SDK in `baseline16.xcresult`. Four are historical raw-pose fingerprints; one
  is the Shape Focus standing-pose oracle. They are not silently rebaselined.
  Skips cover an optional transient legacy asset and the opt-in online video player.
- Main Simulator saved-review hash remains
  `a472d19ff9b2f3495dab0b38d98c306dddfed2e2e0493c8a450ce82f4e9b18cb`.

Result bundles are under `.codex-derived/replayxi-polish170/`. Earlier failed runs
caught export drift, capture framing and blank spatial-glass snapshots; they are
not counted as passing evidence.

[Scene metrics](Evidence170/counter-scene-audit.json) ·
[Header](Evidence170/header-scene-audit.json) ·
[Cutback](Evidence170/cutback-scene-audit.json) ·
[Rebound](Evidence170/rebound-scene-audit.json) ·
[Largest text](Evidence170/view-largest-native.png) ·
[Palette preview](Evidence170/home-deep-native.png) ·
[Recovery before](Evidence170/recovery-before-native.png) ·
[Recovery after](Evidence170/recovery-after-native.png) ·
[Slow gait A/B](Evidence170/recovery-slow-native.gif) ·
[Immersive tactical demo](Evidence170/counter-immersive-native.png) ·
[Free-look POV demo](Evidence170/pov-immersive-native.png) ·
[Asset provenance](../../Assets/ReplayXI/TripoFootballer/Blender/Polish170/asset-manifest.json)
· [Focused suite](Evidence170/focused-suite-summary.json)
· [Full suite](Evidence170/full-suite-summary.json)
· [Pre-pass comparison](Evidence170/pre-pass-failures-summary.json).

## Limits and next checks

The animation is hand-authored, not EAFC-level motion capture. The counterattack
source was reviewed at quarter speed this pass; other sequences use the existing
reference reconstructions. Gaze and unseen bodies remain estimates. More facial and hair
variety needs new player assets. A logged-in Tripo tab was requested; shared-credit
limits still apply. Headset performance and actual pinch ergonomics are unverified.
The Mac lock blocked interactive Simulator checks, not background builds or tests.
User signing/project edits and existing saved reviews are excluded from this backup.

## New-player asset gate

New fictional faces and hairstyles need new geometry, not only these palettes.
Check the live shared balance and quoted cost before each candidate. Keep the
recorded 944-credit reserve, or 30% of the approved starting balance if higher;
verify the ledger before spending. The previous balance is not a live balance.
Finish mesh reduction before rigging: Tripo documents that remeshing
does not preserve bones, weights or animation bindings.
[Tripo conversion guidance](https://docs.tripo3d.ai/export/conversion.html).
Use a standard T-pose candidate, rig-check, Mixamo naming and FBX export, then
verify rest transforms, weights, feet and turns in Blender before native conversion.
[Rig API](https://developers.tripo3d.ai/en/docs/animations-rig) ·
[Pose limits](https://www.tripo3d.ai/help/features/is-it-possible-to-upload-my-existing-model-for-animation).
The API docs are guidance, not proof that the current shared Studio account has
API access. No new account generation was submitted in this pass.

## Backup

The first candidate is in local commit `90a9181`; the reviewed refinements are
saved in a follow-up local commit. Remote push awaits approval for the exact repo.
No user signing/project changes or unrelated projects are included.
