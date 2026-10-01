# Tripo footballer source and native integration

Generated on 1 October 2026 from our [A-pose reference](../../../Docs/ReplayXI/AssetReferences/footballer-a-pose-v1.png),
using the user's authorized shared Tripo account. No third-party game mesh or
real person's scan was used. Applicable account/service terms still govern use;
this record does not claim unrestricted redistribution or commercial rights.

- Asset ID: `7b99bd29-c5db-4c97-8bf4-067618bdeb27` (Private).
- Smart Mesh P2.0; one free trial; requested quad / 8,000 faces.
- Texture: 20 credits. Humanoid / Mixamo auto-rig: 20 credits.
- [Credit ledger](../../../Docs/ReplayXI/TRIPO_CREDIT_LEDGER.json): 40 spent;
  3,050 last observed, from 3,145; 55 of the decrease is not from our jobs.
  No purchase, upgrade or subscription.
- Both GLBs retain the source 4K texture. Rigged export includes the skeleton.

| File | SHA-256 |
| --- | --- |
| `ReplayXI_Footballer_P2_Source.glb` | `e4fbdbcf98c631d283733ff9f339dd2bf01877bf8ab81756b6fe274a25c10eb5` |
| `ReplayXI_Footballer_P2_Rigged.glb` | `132f0c84715f9337ef98366fe7edbb00db9c72fd6d2530bff8ea863d712a4b34` |
| `Tripo_Blender_FBX.zip` | `32f79b8f58897d98e486e29890c279b14c90e5b39e8b9ced44134ff23a7166ba` |

The source imports as 17,082 triangles / 16,702 vertices including UV seams.
Inspect skinning rather than relying on Tripo's displayed polygon count.
White/red kits use identical geometry and scale. New 2K colour atlases are
generated locally by `Scripts/blender/prepare_tripo_kit_candidate.py`.

The user supplied the FBX ZIP after Chrome blocked its download. Its bones
align with the body. The earlier GLB repair and nearest-surface retarget failed
visual QA and remain rejected; do not load those GLBs directly into the app.
No extra Tripo credits were spent on this local integration.

## Native assets

`ReplayTripoAthleteProvider` admits a separate, exact 52-joint rig. It does not
relax the legacy Rocketbox 80-joint contract. Both teams and keepers share the
same 1.82 m body, with white, red and amber 2K kit atlases and geometric numbers.

| Detail | Vertices including UV seams | Triangles | Skin materials |
| --- | ---: | ---: | ---: |
| Near | 9,075 | 7,685 | 1 |
| Low | 3,269 | 1,964 | 1 |

Both have four normalized skin weights per vertex and 512 ground/contact
samples. Each contact set reserves 96 head-weighted samples. Header aiming
uses their actual blended skin positions, not an assumed rigid skull.
Front/back numbers add two draws. Three shared 2K RGBA8 atlases require 48 MiB
at their base level; this excludes mipmaps, staging and renderer caches.

The launcher prepares both LODs and all kits atomically. Failed hashes,
skeletons, contact data, pose solvers or textures leave the existing models
available as a fallback. Balanced mode retains its four-skin cap; Full squad
uses the new skin for all 22 players, or 21 visible teammates/opponents in POV.
No replay, annotation or saved-review schema was changed.

The app validates exact USDZ/motion/contact hashes and exact decoded PNG
pixels. Xcode rewrites PNG encoding, so file hashes alone are unsuitable for
packaged atlases. [NativeBuildReport.json](NativeBuildReport.json) records
source hashes, geometry, UV/atlas correspondence, pose parity and number
clearance. Runtime files live in `ReplayXI/Resources/Players/ReplayXITripo*`.

## Blender sources and rebuild

- [Base rig](Blender/ReplayXITripoFBXBase.blend): valid 1 m local FBX skeleton.
- [Football motion](Blender/ReplayXITripoFootballMotion.blend): relaxed idle,
  v9 running arm swing and finger adjustments. The forward arm sits lower and
  closer to the torso; idle, mesh weights and bind pose are unchanged.
- [Motion report](Blender/MotionBuildReport.json): independently evaluated poses.
- `Scripts/blender/build_tripo_fbx_lods.py`: run against the base blend.
- `Scripts/blender/polish_tripo_fbx_motion.py`: run against the base blend.
- `Scripts/blender/prepare_tripo_kit_candidate.py`: bake the three atlases.
- `Scripts/build_replayxi_tripo_athlete.py`: convert validated GLBs to native
  resources. Use `--help` for its explicit source/report inputs. It requires
  Blender's Python with NumPy and OpenUSD; no online generation is involved.
- `Scripts/audit_replayxi_texture.swift`, compiled with
  `ReplayTexturePixels.swift`, checks source and packaged PNG pixel identity.

Run Blender scripts in an isolated `--factory-startup --background` process.
Outputs must be new directories under `.codex-derived`; the scripts do not
overwrite sources. Preserve the 1 m skeleton throughout Blender work. The
native converter scales mesh, bind and animation translations to 1.82 m once.
Baking that scale into the Blender rig caused stretched limbs and is rejected.

## Verification and limits

USDZ ARKit validation passes. Sampled native skin bounds agree with independent
Blender evaluations within 6.03 micrometres. Simulator tests cover both feet,
headers against actual head triangles, mesh grounding, contacts, rewind,
jersey anchors, 22-player admission, POV visibility and fallback loading.
The two sampled header scenarios meet the sphere within 0.9–5.7 mm without
changing the ball recording. Evidence: `Docs/ReplayXI/Evidence164`.

The cycle165 simulator regression passed 186 tests with no failures, covering
playback, POV switching, annotations, saved reviews, player detail and contacts.
All 15 offline native/source audit tests passed. The generic physical-headset
Release build also passed (unsigned; this is not an on-device performance test).
Existing saved reviews retained their pre-test SHA-256 after testing.

The final cervical correction now rebuilds only the affected head branch:
1 of 52 Tripo joints, or 29 of 80 fallback joints. Forward/reverse samples of
both gaits are exactly equal to the previous full-hierarchy calculation. This
reduces transform work when a correction is needed; it is not a measured FPS gain.

The actual rebound-save test now covers both rigs and both LODs. Tripo's
existing palm markers meet the ball surface within 3.7–4.9 mm in that sampled
save, with planted boots and exact rewind. These are rig markers, not full
hand-mesh collision tests. Current evidence: `Docs/ReplayXI/Evidence165`.

This is a prototype, not EA FC animation quality. A high-knee shirt/shorts
intersection and a partly open running hand remain. Attempts to reweight the
hem worsened it and were rejected. Faceting in the native offscreen renderer
remains visible; imported positions, normals and indices match the
USDZ exactly. A tangent rebuild gave byte-identical images and was not shipped.
On-headset frame rate, comfort and appearance remain unmeasured.
