# Replay XI player asset selection

## Decision

Use the **Microsoft Rocketbox Sports avatars** as the next near-field visual
pilot. Keep Replay XI's original procedural near/mid/far athletes as the
shipping fallback until the imported model passes deformation, debranding,
performance and Vision Pro visual gates.

The 2026-09-10 build now uses the MIT Rocketbox **static face** on near
athletes after prewarm. It supplies facial anatomy, eyes, ears, hair and
normal-map detail while the existing head/neck joints, football gait and
ragdoll drive movement. Its 1,724 vertices and 3,128 triangles replace five
primitive face draws with one shared model. Five small skin palettes match
the current player appearances. The full-body skinned pilot remains separate;
its clip/LOD qualification is not implied by the static-face integration.
See the [asset ledger](THIRD_PARTY_ASSETS.md#bundled-rocketbox-face--2026-09-10).

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

## Sketchfab shortlist — discovery only

The user-supplied Sketchfab catalogue contains potentially useful free models,
but a public model page is not an admitted source asset. According to
Sketchfab's [download API guidelines](https://sketchfab.com/developers/download-api/guidelines),
downloads require an authenticated account, and Creative Commons attribution
must identify the creator, model and source. Replay XI has not authenticated,
downloaded or bundled any of the candidates below. Their page metadata is a
shortlist for a later human-authorized acquisition and archive audit, not proof
that the downloadable archive contains the described rig or animation.

| Candidate | Page-declared licence and metadata | Possible role | Unresolved admission work |
| --- | --- | --- | --- |
| **Football Player — Portugal** by `neshallads` | [Model page](https://sketchfab.com/3d-models/football-player-portugal-5f1a05f9c0964821bbb5322aee27a34e) declares CC BY, download availability, 17.3k triangles and a model “ready to be rigged and animated.” | A higher-detail body/kit silhouette study. | It is not demonstrated as already skinned. Audit the archive format, topology, UVs and material rights; remove national/team identifiers; build and validate an original rig, LODs and animations before runtime consideration. |
| **Rigged Player with basic animations** by `Loudcow67` | [Model page](https://sketchfab.com/3d-models/rigged-player-with-basic-animations-06c3b4bf9e4c4d25ac3768a23ae7375d) declares CC BY, download availability and approximately 1.3k triangles. | A lightweight rig/import and distant-player experiment. | The page has almost no technical provenance. Inspect every archive member, skeleton hierarchy, skin weights, clip names, bind/rest transforms, textures, embedded attribution and actual football suitability. |
| **Soap soccer player** by `luccacatalan` | [Model page](https://sketchfab.com/3d-models/soap-soccer-player-5ae4bf9d6a324cfda79ce1298ea2d333) declares CC BY, download availability, 6.2k triangles and five named clips: kick, push, tackle and two stand-ups. | A bounded football-action importer experiment. | The deliberately toy-like silhouette does not meet near-field realism, and the listed clips omit the idle/run/walk/cut set needed for match playback. Audit the authenticated archive and source chain before even a test-only conversion. |
| **Goalkeeper Stylized — Rig and Animation** by `P-Vi.Art` | [Model page](https://sketchfab.com/3d-models/goalkeeper-stylized-rig-and-animation-7de86f9c36f84152a777f27a73646ada) declares CC BY, download availability, 17.4k triangles, UVs, textures and a rig. | A goalkeeper silhouette and deformation reference. | It is a single stylised goalkeeper, denser than Replay XI's near-player target, and does not establish a reusable field-player family or complete clip set. |
| **Goal Keeper Kick — Blender Rigged** by `SuperScriptDEV` | [Model page](https://sketchfab.com/3d-models/goal-keeper-kick-blender-rigged-13f29f8af55b4b9097802510472fe49f) declares CC BY, download availability, 456 triangles, and rig/animation/ragdoll tags. | A goalkeeper-pose or very-low-detail motion reference. | Tags are not an animation contract. Confirm the archive creator/source chain, playable clips, skeleton ownership, scale, root motion, deformation and whether the visual quality survives a near-field headset view. |

Admission requires all of the following before any Sketchfab candidate can be
copied into the repository or app bundle:

1. A user-authorized, authenticated Sketchfab download through the supported
   site/API flow; do not scrape or bypass authentication.
2. A frozen acquisition record containing model UID, page URL, creator, licence
   text, download time, attribution string and SHA-256 of the original archive.
3. Safe archive extraction plus an inventory of every mesh, texture, animation,
   notice and auxiliary file; reject path traversal, symlinks and undeclared
   executable content.
4. A rights and identity audit for real-player likenesses, club/national marks,
   sponsor art, copied game content and incompatible embedded assets. CC BY on a
   page does not grant separate trademark, publicity or third-party artwork
   rights.
5. A rig audit covering skeleton topology, bind/rest transforms, normalized skin
   weights, root motion, animation clips, finite bounds, metres/Y-up conversion,
   deterministic seeking and visible deformation in RealityKit.
6. Replay XI-authored neutral kits, numbers and LODs, followed by simulator and
   physical Vision Pro profiling under the existing player-fidelity gates.
7. Only after admission, an exact attribution and transformation record added to
   `Docs/ReplayXI/THIRD_PARTY_ASSETS.md` alongside the bundled output hash.

Until that sequence is complete, these candidates remain external links only.
`THIRD_PARTY_ASSETS.md` intentionally has no Sketchfab entry.

Two additional discovery outcomes are explicit rejects. Extremely low-poly,
Minecraft-styled footballers do not improve first-person fidelity. A visually
stronger 44.6k-triangle listing titled **Man Player** reports Character Creator
provenance; a page-level CC BY badge is insufficient evidence that proprietary
base topology and rigging can be redistributed as an application asset. Neither
should enter the acquisition queue. Rocketbox remains the stronger baseline
because Microsoft publishes the source and common rig directly under MIT,
Replay XI already pins every input byte, and the measured near candidate is
approximately 8.1k triangles rather than an unaudited 44.6k-triangle character.

## Pinned Rocketbox pilot

The acquisition script pins Microsoft Rocketbox commit
`0943055db6ec570bcef9f2c8b41c9e5467c808f9` and SHA-256 checks every byte:

```sh
python3 Scripts/fetch_replayxi_rocketbox_pilot.py /tmp/replayxi-rocketbox
python3 Scripts/fetch_replayxi_rocketbox_pilot.py \
  /tmp/replayxi-rocketbox --verify-only
```

The pinned acquisition contains `Sports_Male_02`, `m_idle_breathe_01`, and
`m_run_fast_01` plus the exact upstream MIT notice and six textures. The current
candidate emits the run clip only; the idle file is retained as an audited
future input rather than being misrepresented as a playable resource. The
fetcher intentionally downloads to a staging directory and does not silently
replace an invalid existing file.

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

The full-body Rocketbox pilot is not bundled yet. `Scripts/build_replayxi_rocketbox_pilot.py` now
creates a deterministic, neutral-kit conversion candidate from a private
hash-verified snapshot of all 11 pinned inputs. It strips horizontal root
travel, downsamples and rebuilds four 1,024-pixel textures through a tested
skin-preservation gate, removes source material extensions and specular maps,
and embeds the exact Microsoft MIT notice in both USD metadata and the build
report. The converter also rejects non-finite settings, source/converter races,
unsafe output aliases, symlink publication and invalid per-mesh skinning.

Three independent end-to-end builds were byte-identical at SHA-256
`e338d6a3a4547920a658fea6f9240cefbb0c10c58d4049854ffd0d27b7edd76f`.
The temporary 3.28 MiB USDZ contains two bound meshes with 5,012 total points,
one 80-joint skeleton, one 19-sample / 0.6-second run animation, four neutral
textures and at most four normalized influences per point. `usdchecker --arkit`
and the OpenUSD skinning audit pass.

### 2026-09-05 RealityKit qualification

A fresh acquisition into `/private/tmp` verified all 11 pinned inputs and a
third independent build reproduced the same 3,439,236-byte output and SHA-256.
The build report measured two directly bound meshes, 80 joints, four normalized
influences per point, 19 animation samples, zero residual horizontal root
travel, and a non-zero OpenUSD skinning-transform delta of
`202.1090957682905`.

The exact candidate was then staged only in a disposable XCTest bundle and
loaded on an Apple Vision Pro simulator running visionOS 27.0. RealityKit
decoded it as one coalesced `ModelEntity`, reported bounds of 1.348 × 1.821 ×
0.338 metres, exposed two finite animation resources of
0.6000000238 seconds each, and accepted deterministic paused seeks at 0.001,
0.15, 0.30, 0.45 and 0.599 seconds on both controllers. The focused test passed
1/1 in 0.46 seconds; that is whole-test duration, not an isolated decode
benchmark. The staged binary and Derived Data were removed from the worktree
after the run. The opt-in test remains in
`ReplayImportedAthleteProviderTests.swift`; without the exact transient fixture
it reports a skip rather than weakening its hash lock.

This clears source identity, deterministic build, USD skinning, RealityKit
decode, finite-controller and seek gates. It does **not** prove rendered
deformation quality: the simulator unit-test API cannot inspect post-skinning
vertices, and no frame-by-frame visual capture or physical Vision Pro run was
performed. The candidate therefore remains outside the repository and app
bundle until animated visual identity, dynamic team-kit separation, authored
LODs, 22-player performance and physical-device gates pass.

An additional Apple Metal `usdrecord` probe rendered the exact candidate at
time codes 0, 4.5, 9, 13.5 and 18. All five frames retained coherent skin,
recognisable limbs, the neutral kit and stable textures; no exploded vertices
or skeleton collapse was visible. This is useful deformation evidence but not
a runtime grounding pass: the standalone USD origin sits near the pelvis,
whereas `ReplayImportedAthleteProvider` applies a bounds-derived sole offset
when it creates an app instance. The capture therefore does not prove planted
foot contact, in-app team-kit differentiation, animation blending or headset
frame time. The only emitted clip also remains a short fast run, so the asset
stays quarantined until a grounded in-app capture covers idle, acceleration,
run, deceleration, cut and football-action transitions.

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

## Current motion evidence

### Full-body Roleplay staging — 2026-09-10

`Scripts/build_replayxi_skinned_athlete.py` now emits a complete skinned
Rocketbox athlete and local-pose data from the pinned sports body, idle and
run sources. It uses one clean 80-joint USD skeleton, two directly bound
meshes (5,012 vertices / 8,146 triangles), and metre/Y-up coordinates.
`ReplayXIRocketboxMotion.json` contains exact exported joint paths, parent
indices, rest TRS, bone-local axes, semantic joint mapping, foot contacts,
shirt-surface number anchors, 83 idle frames and 19 run frames. Horizontal
root movement is removed; the run's 7.18 cm vertical cycle is retained.

Three home/away/keeper palettes each support all five skin appearances. The
15 body maps are 512px; they can share the existing five detailed head maps.
Both USDZ and JSON reproduced byte-for-byte across repeated builds before
the final number-anchor fit refinement. ARKit validation, skin-weight and
exact USD/JSON joint-order checks pass. Reviewed offline idle/run previews show
recognisable, coherent deformation; the Metal preview still shows faceted
cloth shading, so material/shading review remains open.

The staged output is in `.codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/`.
It is deliberately outside the app bundle while the requested real-match
Roleplay/Blender work takes priority. No new default runtime rendering path is
claimed by this asset-build step.

Known-working build dependencies are Python 3.9.6, `numpy==2.0.2`,
`Pillow==11.3.0`, `usd-core==26.8`, Assimp 6.0, and Apple's
`/usr/bin/usdzip` / `/usr/bin/usdchecker`. Blender output uses Blender 5.2.1
LTS. To recreate the Python environment and run the three non-skipping math
tests from the repository root:

```sh
/usr/bin/python3 -m venv .codex-derived/ReplayXI-Assets/BuildEnv
.codex-derived/ReplayXI-Assets/BuildEnv/bin/python3 -m pip install --no-cache-dir 'numpy==2.0.2' 'Pillow==11.3.0' 'usd-core==26.8'
PYTHONPYCACHEPREFIX=/private/tmp/replayxi-asset-pycache .codex-derived/ReplayXI-Assets/BuildEnv/bin/python3 -m unittest discover -s Scripts/tests -p test_replayxi_skinned_athlete.py -v
```

For a fresh full-body build, use a new output directory; the builder rejects
existing Rocketbox outputs. The extra Assimp export below supplies the named
geometry manifest consumed by the Blender builder. It is separate from the
USD builder's private, temporary Assimp exports:

```sh
replayxi_python=.codex-derived/ReplayXI-Assets/BuildEnv/bin/python3
replayxi_source=.codex-derived/ReplayXI-Assets/RebuildSource
replayxi_output=.codex-derived/ReplayXI-Assets/Rebuilt
"$replayxi_python" Scripts/fetch_replayxi_rocketbox_pilot.py "$replayxi_source"
PATH=/opt/homebrew/bin:/usr/bin:/bin PYTHONPYCACHEPREFIX=/private/tmp/replayxi-asset-pycache "$replayxi_python" Scripts/build_replayxi_skinned_athlete.py "$replayxi_source" "$replayxi_output"
/opt/homebrew/bin/assimp export "$replayxi_source/Assets/Avatars/Professions/Sports_Male_02/Export/Sports_Male_02.fbx" "$replayxi_source/model.gltf" -fgltf2
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --python-exit-code 1 --python Scripts/blender/prepare_football_player.py -- --source "$replayxi_source" --staged "$replayxi_output" --output "$replayxi_output/Blender" --render
```

USDZ, pose JSON, `.blend` and GLB outputs remain ignored under
`.codex-derived/`; the committed scripts and pinned MIT source records are
their rebuild path. Blender also reuses the committed, derived Rocketbox head
palette. This is a version-recorded recipe, not a fully hermetic toolchain:
Blender files and GLBs are verified for content/deformation, not promised to
have identical binary hashes across Blender or exporter versions.

### Editable Blender players — 2026-09-10

`Scripts/blender/prepare_football_player.py` builds an isolated Blender 5.2
library from the same audited geometry and named motion contract. It does not
modify the user's open scene or preferences. The generated library lives in
`.codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/`:

- `ReplayXIFootballPlayers.blend`: home/away/keeper collections with shared
  body/head geometry, object-local kit materials and independently editable
  front/back numbers attached to the chest bone.
- `ReplayXIFootballPlayers.json`: coordinate, action, geometry and attribution
  contract, including precise semantic bone names.
- `ReplayXIFootballPlayerHome.glb`, `ReplayXIFootballPlayerAway.glb`,
  `ReplayXIFootballPlayerKeeper.glb`: approximately
  1.48 MB each, for MCP safe-mode import. Each includes one 80-bone skin, both
  animation clips, four meshes (body/head/two numbers) and embedded textures.
- `ReplayXIFootballPlayer-idle.png` and `-run.png`: inspected CPU renders.

The model faces Blender -Y in metre/Z-up space. Keep the root's +0.0164364 m
sole offset when placing it on the pitch. `ReplayXI_Idle` spans frames 1–83;
`ReplayXI_Run_InPlace` spans frames 1–19, both at 30 fps. Text objects carry
`replayxi_kind=jersey_number`; copy their font data before changing each
player's digits. When copying a collection, remap parents and armature
modifiers, then explicitly restore `matrix_parent_inverse` **and**
`matrix_basis`. This prevents Blender's copied bone-parent cache from moving
the number off the shirt.

Evaluated skin positions match source linear-blend skinning within 0.0000012 m
over six sampled poses. Shirt anchor error is below 0.0000003 m. Smooth source
normals fix the faceted-cloth appearance in Blender previews. Post-save tests
append all three templates, move/rotate them, check independent kits/numbers,
then re-import all three GLBs and confirm actual animated mesh deformation.
This is a usable Blender demo asset, **not** a claim of a football mocap suite,
physics ragdoll, or completed Vision Pro runtime integration.

Rebuild and test with the audited source directory already prepared:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --python-exit-code 1 --python Scripts/blender/prepare_football_player.py -- --source /private/tmp/replayxi-rocketbox-loop31 --staged .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final --output .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender --render
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --python-exit-code 1 --python Scripts/blender/test_football_player.py -- --library-dir .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender
```

The default procedural athlete no longer replaces an entire gait pose when a
telemetry sample crosses the semantic idle/walk, walk/jog, jog/sprint or cut
classification boundary. `ReplayAthleteMotion` now blends stride, support time,
knee lift, ankle roll, torso lean, counter-rotation and arm mechanics through
continuous speed and turn bands. The blend is still a pure function of match
time and telemetry, so reverse playback and SharePlay resynchronisation do not
need mutable transition state. A focused simulator regression samples both
sides of every semantic boundary and constrains root and joint discontinuity.

The procedural near athlete also has a separately articulated neck/head chain,
bounded deterministic scanning, ball-aware gaze, football-specific heel strike,
toe-off and sprint flight, plus a deterministic ragdoll blend. These are code-
and simulator-test claims, not a claim of captured professional mocap.

The full-body higher-fidelity asset requirement is **not yet complete**. The bundled CC0
pilot is still a one-player, run-only diagnostic that falls back to the
procedural athlete for idle, walk, cut and ragdoll states. The selected
Rocketbox full-body candidate is not in the app bundle. Its deterministic RealityKit load
and seek probe now passes, but rendered deformation, authored
idle/cut/football-action clips, dynamic team-kit separation, authored LOD,
22-player memory/frame-time, and physical Vision Pro review remain open. No
Sketchfab candidate has passed the authenticated acquisition and rights gates.

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
