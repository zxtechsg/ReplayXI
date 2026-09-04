# Replay XI player asset selection

## Decision

Use the **Microsoft Rocketbox Sports avatars** as the next near-field visual
pilot. Keep Replay XI's original procedural near/mid/far athletes as the
shipping fallback until the imported model passes deformation, debranding,
performance and Vision Pro visual gates.

This decision does not permit EA Sports/FIFA models, animations, textures,
logos, likenesses or extracted game data. Educational use does not make copied
commercial game assets safe to redistribute. The selected sources below carry
their own explicit reusable licences.

## Candidate audit

| Candidate | Licence and direct source | Format / rig | Replay XI fit | Disposition |
| --- | --- | --- | --- | --- |
| **Microsoft Rocketbox** | [MIT licence](https://github.com/microsoft/Microsoft-Rocketbox/blob/master/LICENSE.md); [Microsoft repository](https://github.com/microsoft/Microsoft-Rocketbox) | 115 rigged FBX avatars, common Biped rig, texture sets, and 417 compatible FBX animations. The repository includes four `Sports_Male` and two `Sports_Female` variants. | It is the only audited option that already contains recognisable football shirts, shorts, socks and boots. Relatively low geometry and a shared rig make a 22-player scene credible. Source kit art must be repainted to Replay XI branding. | **Selected for a non-shipping pilot.** Direct raw downloads work without an account and the repository permits redistribution with the MIT notice. |
| **MakeHuman / MPFB** | Bundled assets and generated output are [CC0](https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md); the generator code is AGPL but is not shipped. | Parametric humans exported through FBX/DAE/OBJ/MHX2; MPFB offers a GameEngine rig and game proxies such as 741- and 1,591-face bodies. | Best route to original athlete body/head diversity and long-term art ownership. It still needs a football kit, hair, authored LODs, mocap and an offline Blender export pipeline. Only bundled CC0 assets may enter the automated recipe; community assets need their own audit. | **Second choice for a bespoke production set**, not a quick playback upgrade. |
| **Quaternius Universal Base Characters + Universal Animation Library** | Both are [CC0](https://quaternius.com/faq.html); [base characters](https://quaternius.com/packs/universalbasecharacters.html) and [animations](https://quaternius.com/packs/universalanimationlibrary.html) are direct creator pages. | FBX/glTF humanoids averaging 13k triangles, 20 hairstyles, and 120+ retargetable locomotion/action clips. | Useful as a repaired conversion fixture, but the proportions and texture treatment remain deliberately stylised. Simulator visual QA also rejected the current pilot's shoulder and kit silhouette for the normal demo. | **Quarantined to an explicit one-player diagnostic override. Keep the improved procedural athlete as the default and use the fixture for importer regression tests.** |

Blender Studio's Rain rig was also considered. It is a polished CC-BY practice
rig, but it is a single stylised character with a complex animation control rig,
no football kit, no authored match LODs and no football locomotion set. It is a
poor 22-player runtime source despite its visual quality.

## Pinned Rocketbox pilot

The acquisition script pins Microsoft Rocketbox commit
`0943055db6ec570bcef9f2c8b41c9e5467c808f9` and SHA-256 checks every byte:

```sh
python3 Scripts/fetch_replayxi_rocketbox_pilot.py /tmp/replayxi-rocketbox
python3 Scripts/fetch_replayxi_rocketbox_pilot.py \
  /tmp/replayxi-rocketbox --verify-only
```

The pilot uses `Sports_Male_02`, `m_idle_breathe_01`, and `m_run_fast_01` plus
the exact upstream MIT notice and six textures. It intentionally downloads to a
staging directory and does not silently replace an invalid existing file.

Measured from the pinned files with Assimp 6.0.5:

- character FBX: 538,656 bytes, centimetre-authored, approximately 1.80 m tall;
- two skinned mesh primitives, 5,755 imported vertices, 8,146 triangles;
- one 80-joint skin after FBX-to-glTF conversion, 89 imported scene nodes;
- no alpha-hair material on this variant, avoiding a third draw and transparent
  overdraw;
- fast-run clip: 0.6 seconds after conversion, with 86 animated source nodes;
- six 2,048 × 2,048, 24-bit TGA textures: 72 MiB without mipmaps.

The repository README discusses `hipoly`, `midpoly`, `lowpoly` and
`ultralowpoly` names, but the inspected `Sports_Male_02.fbx` exposes only the
`m301_hipoly_81_bones` geometry. Replay XI must author and validate its own LODs
instead of assuming the other levels are in the export.

## Interim runtime pilot

Rocketbox is not bundled yet. `Scripts/build_replayxi_rocketbox_pilot.py` now
creates a deterministic, neutral-kit conversion candidate from a private
hash-verified snapshot of all 11 pinned inputs. It strips horizontal root
travel, downsamples and rebuilds four 1,024-pixel textures through a tested
skin-preservation gate, removes source material extensions and specular maps,
and embeds the exact Microsoft MIT notice in both USD metadata and the build
report. The converter also rejects non-finite settings, source/converter races,
unsafe output aliases, symlink publication and invalid per-mesh skinning.

Two independent end-to-end builds were byte-identical at SHA-256
`e338d6a3a4547920a658fea6f9240cefbb0c10c58d4049854ffd0d27b7edd76f`.
The temporary 3.28 MiB USDZ contains two bound meshes with 5,012 total points,
one 80-joint skeleton, one 19-sample / 0.6-second run animation, four neutral
textures and at most four normalized influences per point. `usdchecker --arkit`
and the legacy structural audit pass. The asset remains outside the repository
and app bundle until RealityKit load, animated deformation, visual identity,
LOD and performance gates pass in the simulator and on physical Vision Pro.

The repaired CC0 `ReplayXIPlayerKitPilot.usdz` remains bundled as a converter
and importer diagnostic, but `ReplayImportedAthleteProvider` does not admit it
by default in development or release builds. The app-bundle copy is
byte-for-byte locked to SHA-256
`afeec6489a68c2ac121dad713021c7a5a6ff65ae3f031d3758ccdabfa4574cc1`.
It loads once before the immersive space, shares mesh/texture resources through
RealityKit clones, replaces the authored kit-shell materials per team, adds
dynamic Replay XI geometric front/back numbers, and manually seeks each paused
skeleton track from the telemetry-distance gait phase.

The explicit diagnostic integration cap is one imported selected/nearest player. The fixture still
has three 65-joint skeleton copies and seven textures decoding to 20.5 MiB, so
using it for 22 players is explicitly unsupported. All build configurations default off;
`REPLAYXI_IMPORTED_PLAYER_PILOT=1` or the developer preference key
`ReplayXI.ImportedPlayerPilotEnabled` provides an explicit override. A failed
prewarm returns to the existing procedural athlete without changing playback.

## Integration recipe

1. **Acquire and preserve provenance.** Run the pinned fetcher, then the audited
   pilot builder. Preserve its source commit, input/converter hashes, exact MIT
   notice and output report next to every reviewed USDZ.
2. **Review the neutral kit.** Inspect the generated neutral textures and skin
   mask on the animated mesh. Author home, away and goalkeeper palettes without
   reproducing real-club or EA artwork. Keep Replay XI's extruded jersey number
   entity so player identity remains dynamic and readable.
3. **Normalise the skeleton.** Scale centimetres to metres, preserve one Biped
   hierarchy, limit skin weights to four influences, and emit an explicit map
   from Biped joints to Replay XI's hips/spine/head, limb and ragdoll proxy
   contract. Remove facial/finger deform joints from mid/far exports only after
   a weight audit proves no vertex still references them.
4. **Prepare deterministic motion.** Retarget the provided idle and run clips,
   strip animation root translation because telemetry owns world position, and
   use clip phase and playback rate derived from match time and player speed.
   Add football-specific plant, cut, pass and strike clips only from separately
   audited sources or original capture. The existing procedural motion remains
   the fallback when a clip is absent.
5. **Author LODs rather than cloning the near mesh 22 times.** Initial targets:
   near ≤8.2k triangles / 80 joints / two materials; mid ≤3.5k triangles /
   ≤32 deform joints / two materials; far ≤1.2k triangles / ≤18 deform joints /
   one atlas material. Share mesh, textures and animation resources across
   clones. Use only one to four near athletes depending on Shared versus Full
   Space; the rest use mid/far.
6. **Rebuild PBR textures.** Downsample body/head base colour and normal maps to
   1,024 for near and 512 for mid. Convert legacy specular to a reviewed
   metalness/roughness representation instead of copying it blindly. Far LOD
   uses one small atlas and no normal map. Twenty-two players must share these
   resources; do not bake 22 unique kit textures.
7. **Convert and validate.** Export glTF with one skin, then build USDZ through
   the existing hash-locked OpenUSD path. Run `usdchecker --arkit`, the Replay XI
   archive/topology audit, RealityKit load/seek tests, and an animation-bounds
   sweep before placing it in the application bundle.
8. **Integrate behind a feature gate.** Load/prewarm each USDZ once, clone the
   loaded resource, and keep telemetry movement on the player root. The skinned
   visual may play authored motion while Replay XI's named lightweight joint
   proxy continues to drive interaction, first-person camera attachment and
   deterministic ragdoll presentation.

## Admission gates

The pilot is not production-ready until all of these are true:

- idle, sprint, turn, seek, reverse-seek and loop-boundary frames show no
  exploded skin, foot slide, floor penetration or bounds spikes;
- first-person playback never couples recorded head rotation to the user's
  headset view;
- shirt number and selected-player outline remain legible at near, tactical and
  touchline scales;
- 22-player playback stays within Replay XI's existing Shared/Full Space scene
  envelopes and is profiled with RealityKit Trace on physical Vision Pro;
- resource clones share geometry, texture and animation allocations;
- imported-player failure returns to the procedural athlete without affecting
  playback, annotation selection or collaboration state;
- `THIRD_PARTY_ASSETS.md` contains the exact derived output hashes, the MIT
  notice path, converter identity and any texture/mesh transformation record.

Until then, `Sports_Male_02` is an audited art-pipeline input, not a claim that
Replay XI already ships a FIFA-like simulation model.
