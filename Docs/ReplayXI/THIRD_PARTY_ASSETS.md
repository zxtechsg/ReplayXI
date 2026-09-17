# Replay XI third-party player asset ledger

## Bundled static far-face derivative — 2026-09-17

`ReplayXIFarAthleteHead.usdz` is a reduced copy of the existing MIT Rocketbox
static head below. No additional third-party source or download was used.

- Current package: 21,563 bytes; SHA-256
  `30b5213f5967da5fa2574f39dfe942b989fe94629994cd10ad7a739c45e32b3f`.
  Loop122 removes the discarded embedded textures from the original Loop116
  package (540,760 bytes, hash
  `0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce`).
- 486 vertices /749 triangles /one mesh /one material /zero bones.
  The complete far player remains seven model entities, now820 vertices and
  1,225 triangles, inside its existing geometry budget.
- Reproduction: `Scripts/blender/build_static_far_head_candidate.py`, then
  `Scripts/build_replayxi_far_head_mesh_only_candidate.py`. The second step
  preserves exact geometry, UVs, normals, transforms and material binding while
  replacing only the unused imported material with a neutral PBR placeholder.
  The existing bundled MIT notice applies. Original source files are unchanged.
- Explicit cold preparation, strict hash/native-instance checks and cached mesh.
  Runtime heads share existing five skin palettes and normal map; make/update
  do not load files. This package contains no embedded images; the shared palette
  provider still prepares its normal textures. No peak-memory/load-time saving
  is inferred from the smaller package alone.
- Head-local Y0.125m, mesh X1.07, existing head/neck motion. Near/mid unchanged;
  failure keeps the original ellipsoid. No extra skeleton or facial animation.
- Native full-body collar/running checks and source/candidate crops are recorded
  in Loop114/116. Loop122 additionally verifies exact imported tangent/bitangent
  equality and six paired native images with zero changed channels. This is a
  simplified far-distance face, not detailed near
  facial fidelity or a claim of measured headset performance.

## Bundled lower-detail Rocketbox derivative — 2026-09-17

`ReplayXIRocketboxLow.usdz` and `ReplayXIRocketboxLowContactSurface.json`
derive from the same MIT source and original neutral Replay XI kit below.
No new third-party content was downloaded. The bundled MIT notice still applies.

- USDZ: 1,263,724 bytes; SHA-256
  `cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac`.
- Full contact profile: 265,785 bytes; SHA-256
  `76e9cfe574345931ca945495f41a0e2fe872a182d8db4f7e3078a8baa4acf7b1`.
- 1,707 vertices / 2,129 triangles / 80 original joints / two material sections.
  Two geometric shirt numbers are added at runtime. Existing body/face palettes
  and normal maps are reused, rather than a new set of decoded team textures.
- Blender decimation preserves protected neck, shoulder and crotch seams.
  Canonical USD bind/rest transforms and motion blocks are preserved. All
  1,707 weighted vertices participate in this derivative's floor contact.
- Reproduction and explicit limitations: Loop102; native geometry/pose
  admission: Loop109; full-contact validation: Loop112; runtime integration:
  Loop113. This is a simplified licensed model, not FIFA-quality or football mocap.
- Optional cold-path preparation is independent of the near body. Failed hash,
  skeleton, material or contact admission leaves the existing fallback usable.
  The four-skin total and two-skin player-POV caps are not increased.

## Bundled single-skeleton Rocketbox body — 2026-09-10

`ReplayXIRocketboxAthlete.usdz`, `ReplayXIRocketboxMotion.json`,
`ReplayXIRocketboxContactSurface.json` and the fifteen
`ReplayXIRocketbox{Home,Away,Keeper}Skin{0...4}.png` files in
`ReplayXI/Resources/Players/` derive from the pinned Microsoft Rocketbox source
below. They are distinct from the older run-only pilot described later.

- Source: [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox),
  commit `0943055db6ec570bcef9f2c8b41c9e5467c808f9`; `Sports_Male_02`,
  `m_idle_breathe_01` and `m_run_fast_01`.
- Licence: upstream MIT, retained in USD metadata and the already-bundled
  `LICENSE-ROCKETBOX-MIT.txt`. No EA/FIFA assets or club/sponsor art are used.
- Reproduction: `Scripts/build_replayxi_skinned_athlete.py`; neutral kits and
  skin palettes are authored by the repository's conversion scripts.
- USDZ: 1,385,975 bytes; SHA-256
  `7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772`.
- Motion JSON: 791,827 bytes; SHA-256
  `d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4`.
- Contact JSON: 33,957 bytes; SHA-256
  `71eb134afa27eac0c23500afbd038dd11594a2b5ad30a5a178b303305a49c3ca`.
  It retains 339 real skin vertices and 603 weighted influences from the same
  licensed mesh. `Scripts/blender/build_player_contact_surface.py` reproduces
  it from the audited Blender library and runtime pose attachments. Calibration
  covers 206 poses, with less than 3 mm of omitted surface depth and 6 mm padding.
- 80 joints, 5,012 vertices, 8,146 triangles; shared body/head material sections.
  Smooth vertex normals, normalized weights, common skeleton binding, embedded
  neutral colour/normal maps and source joint ordering are audited after packaging.
- RealityKit import must retain mesh parts `Body` (slot 0, 3,288 vertices) and
  `Head` (slot 1, 1,724 vertices), with the sidecar's exact 80 joint names. The
  provider rejects unexpected layouts rather than guessing material mappings.
- Fifteen body palettes and five reused face palettes are shared. The base-level
  texture estimate is 25 MiB (including the 1024px body normal), excluding mipmaps
  and importer/cache overhead. Skin and jersey numbers reserve four material draws
  per visible instance. These are asset estimates, not headset frame-time claims.

The app integration uses absolute-time idle/run poses, bounded head look and
chest-attached geometric shirt numbers. Walks, cuts and ball actions retain the
skin through football-leg retargeting. Reviewed impacts retarget the existing
fixed-step solver onto the same skin, with weighted surface contact. The old
procedural football rig remains an asset-failure fallback and a kinematic query
body. Retargeted motion is not football mocap or a captured get-up animation.
The near-subject cap is two in player POV and four in other views; distant players
retain their lower-cost representation. Physical-headset performance and broader
football motion coverage remain open qualification work.

## Conversion-validation asset

| Repository path | Upstream work | Creator | License | Replay XI modification |
| --- | --- | --- | --- | --- |
| `ReplayXITests/Fixtures/ThirdParty/Quaternius/ReplayXIPlayerSprint.usdz` | [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html), free Standard `Superhero_Male_FullBody`, plus [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html), free Standard `Sprint_Loop` | [Quaternius](https://quaternius.com) | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/); local notice: `ReplayXITests/Fixtures/ThirdParty/Quaternius/LICENSE-CC0-1.0.txt` | Test-only technical conversion fixture: retargeted animation, hierarchy-preserving GLB-to-USD conversion, corrected USD/RealityKit schema metadata and USDZ packaging. It is excluded from the app bundle. No EA/FIFA model, texture, animation, logo, likeness, or extracted game data is included. |
| `ReplayXITests/Fixtures/Generated/ReplayXIPlayerKit.usdz` | Derived from the same CC0 character and sprint fixture | Quaternius + Replay XI-authored kit shell | CC0 1.0 Universal | Golden converter fixture for the opaque jersey, shorts, socks, boots and trim shells generated by `Scripts/style_replayxi_football_kit.py`, retaining the weighted topology. |
| `ReplayXI/Resources/Players/ReplayXIPlayerKitPilot.usdz` | Byte-identical, hash-locked copy of the generated fixture above | Quaternius + Replay XI-authored kit shell | CC0 1.0 Universal; bundled notice: `ReplayXI/Resources/Players/LICENSE-QUATERNIUS-CC0-1.0.txt` | Explicit opt-in diagnostic only; it is not the default in any build configuration. `ReplayImportedAthleteProvider` loads it once and clones shared resources after the developer override is set. RealityKit coalesces the five authored kit meshes into material slots 1–5 of one six-slot skinned body model while preserving their names as empty child markers; the provider verifies that exact hash-locked topology, preserves base-body slot 0, and overrides jersey/shorts/socks/boots/trim with original Replay XI team colours. It adds original font-free geometric numbers and seeks both animation resources exposed by RealityKit from telemetry time. It is capped at one selected/nearest player; the procedural athlete remains the full-squad default and failure fallback. |

## Non-bundled Rocketbox pilot

`Scripts/build_replayxi_rocketbox_pilot.py` is an audited conversion pipeline
for Microsoft Rocketbox `Sports_Male_02` and `m_run_fast_01` at pinned commit
`0943055db6ec570bcef9f2c8b41c9e5467c808f9`. The upstream model, animation,
textures and exact Microsoft MIT notice remain governed by that notice. The
builder consumes only private hash-verified input and converter snapshots,
neutralises source kit artwork, preserves skin pixels, strips horizontal root
motion, audits both mesh bindings and packages an ARKit-valid deterministic
USDZ. Its 43-test suite includes licence, texture, topology, skin-weight,
publication and source-race coverage.

Three independent temporary builds produced SHA-256
`e338d6a3a4547920a658fea6f9240cefbb0c10c58d4049854ffd0d27b7edd76f`.
The latest output is 3,439,236 bytes. A disposable visionOS 27.0 simulator
XCTest load admitted that exact hash, measured 1.348 × 1.821 × 0.338-metre
bounds, observed one RealityKit-coalesced `ModelEntity`, exposed two finite
0.6000000238-second animation resources, and deterministically sought both at
five clip times. The focused test passed 1/1. The transient fixture was removed
immediately afterward; that full-body skinned Rocketbox pilot is not bundled.
All 43 acquisition, conversion, archive and packaged-skinning tests also pass
when this temporary output is supplied through the integration-test gate.

OpenUSD proves non-static skinning transforms, but the RealityKit unit-test API
does not expose deformed vertex positions. Admission still requires rendered
frame review, dynamic team-kit separation, authored LODs, 22-player profiling,
and physical Vision Pro validation. Until then the procedural athlete remains
the default for body motion, and the full-body Rocketbox pilot remains experimental.

## Bundled Rocketbox face — 2026-09-10

`ReplayXI/Resources/Players/ReplayXIAthleteHead.usdz` is a separate static
head extracted from the same hash-verified MIT `Sports_Male_02` source. It
replaces the primitive near-player face with authored facial anatomy, eyes,
ears and short hair. It attaches directly to Replay XI's existing moving
head joint; the existing neck joint, gait, football actions and ragdoll remain
responsible for motion. This asset adds no animation controller or skinning
pass and contains no source kit or sponsor art.

Its textured neck meets the shirt collar directly. The old procedural neck
shell is omitted for this asset, avoiding a second skin surface under the jaw.

`Scripts/build_replayxi_athlete_head.py` verifies the 11 pinned source inputs,
extracts only the head material primitive through Assimp 6.0, verifies its
consumed geometry/UV values, converts Z-up centimetres to head-local Y-up
metres, corrects the vertical UV convention, and packages it with Apple's
USD tools. A 512px normal map and five 512px skin palettes preserve facial
detail while matching the existing athlete appearances. The source MIT
notice is in USD metadata and bundled as `LICENSE-ROCKETBOX-MIT.txt`.

- Source commit: `0943055db6ec570bcef9f2c8b41c9e5467c808f9`.
- Source: [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox).
- USDZ: 586,688 bytes; 1,724 vertices; 3,128 triangles; one material.
- Near athlete, worst-case `88` shirt/chest numbers: 24 model entities,
  4,550 vertices and 5,728 triangles. Invisible backs of the raised number
  glyphs are omitted; their visible fronts and side walls are unchanged.
- USDZ SHA-256: `7446de58f31366aacf733060a12748b62c3dfb75a46994ba3ed32576355c1f20`.
- All face resources together: approximately 1.8 MiB on disk; at most 7 MiB
  decoded base-level textures shared across players, before mipmaps.
- `ReplayAthleteHeadProvider` loads once before the room opens and shares one
  mesh and five material instances. Any preparation failure keeps the original
  procedural face. Mid/far players retain their low-cost geometry.
- `usdchecker --arkit` passes. Metal image review verified facial proportions,
  eye/mouth placement, neck UVs and normal-map shading. In-app fit and motion
  are covered by `ReplayAthleteHeadTests`; physical headset profiling remains
  required before making a device frame-rate claim.

This is a face-fidelity improvement, not admission of the full Rocketbox body
or its run-only motion clip. The existing full-body pilot requirements remain.

The Quaternius pages identify both packs as CC0 and explicitly permit personal,
educational, and commercial use. The character pack is humanoid-rigged,
animation-ready and compatible with the animation library.

> **Integration gate:** visual QA rejected the original legacy conversion. The
> repaired asset now enters only a hash-locked, explicit developer diagnostic,
> not the normal demo or shipping 22-player path. USD, archive, topology and RealityKit load/clone/seek
> tests do not replace animated physical Vision Pro review. Every build configuration
> keeps the gate off by default, and any load, hash, bounds, shell or animation failure
> must leave Replay XI's grounded procedural rig untouched.

### Source identity

The inputs used to produce the checked-in asset are independently identifiable
by these hashes:

| Input | SHA-256 |
| --- | --- |
| `replayxi-night-striker.glb` | `a466828c67a4acc9b2413212ce6d9cde235e3aed9b675680c14fd9673858f118` |
| `replayxi-universal-animation-library.glb` | `4c748767741a3e495d89667b9a218b690ba9810b9517a12e960780e3ca72c4e9` |
| Checked-in `ReplayXIPlayerSprint.usdz` | `841c7295bd9cc5abaf8bfad379f328de3825ce3a9da03ad1eeb05689fdc84ff9` |
| Checked-in `ReplayXIPlayerKit.usdz` | `afeec6489a68c2ac121dad713021c7a5a6ff65ae3f031d3758ccdabfa4574cc1` |
| Bundled `ReplayXIPlayerKitPilot.usdz` | `afeec6489a68c2ac121dad713021c7a5a6ff65ae3f031d3758ccdabfa4574cc1` |

The audited source archive hashes were `fdbf1804c90dfc1ea03e992bff7da2dfd1a79318e13270a660180f9308455f40`
for Universal Base Characters and
`cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724`
for Universal Animation Library. The transformed GLBs and these hashes are
also documented in the upstream project's
[asset ledger](https://github.com/Seyamalam/blood-league-kickoff/blob/main/docs/ASSET_CREDITS.md).

### Transformation record

`Scripts/replayxi_glb_retarget.py` copies the selected animation onto the
matching Quaternius humanoid joints. It preserves target bind-pose rotations,
translations and bone lengths, applies source rotation deltas, and only copies
translation motion for `root` and `pelvis`. It rejects incompatible skin
hierarchies, malformed or sparse accessors, duplicate/incomplete animation
channels, non-finite samples and unsupported interpolation. It also keeps
equivalent quaternion samples in one hemisphere so downstream interpolation
does not take a long arc. This avoids proportion stretching and catches corrupt
inputs before conversion.

`Scripts/build_replayxi_player_usdz.py` then:

1. rejects source files whose hashes do not match this ledger;
2. checks out-of-process converter identity;
3. retargets one named clip;
4. converts it to binary USD using
   [`kcoley/gltf2usd`](https://github.com/kcoley/gltf2usd) at commit
   `c0752099313834a466acf04b89af33dfd5dc9a0b` (MIT), with narrow OpenUSD 26
   typed-array compatibility fixes in a temporary copy. The patch now preserves
   `/` separators in joint paths and gives each separately skinned mesh a unique
   joint-root namespace;
5. removes the converter's redundant animated Xform copy of the joint graph;
6. establishes Y-up, metres, a default prim, skin/material schema APIs and
   correct normal-map shader metadata;
7. verifies joint topology, rest/bind matrices, skin indices, normalized
   weights and non-static joint transforms with OpenUSD;
8. packages and validates the result with Apple's `usdzip --arkitAsset` and
   `usdchecker --arkit -t`; and
9. runs the dependency-free `Scripts/audit_replayxi_player_usdz.py` structural
   admission check on the finished archive.

`Scripts/replayxi_usdz_archive.py` normalizes only the ZIP local/central DOS
timestamps after `usdzip` runs. Payloads, CRCs, alignment padding and member
offsets are unchanged, while identical inputs now produce byte-identical USDZs.
Two independent legacy repairs produced the checked-in sprint hash above.

Example invocation (dependencies are deliberately not vendored):

```sh
PYTHONPATH=/path/to/python-dependencies python3 \
  Scripts/build_replayxi_player_usdz.py \
  /path/to/replayxi-night-striker.glb \
  /path/to/replayxi-universal-animation-library.glb \
  /path/to/gltf2usd \
  /tmp/ReplayXIPlayerSprint.usdz \
  --clip Sprint_Loop
```

Python dependencies are `numpy`, `Pillow`, `pygltflib`, and `usd-core`. The
same command can build `Idle_Loop`, `Jog_Fwd_Loop`, or another compatible named
clip without modifying the runtime source asset.

### Identified deformation cause and legacy repair

OpenUSD defines skeleton topology through relative joint-path tokens such as
`Shoulder/Elbow/Hand`; path ancestry is what makes `Hand` a descendant of
`Elbow`. Bind transforms are joint world-space transforms, while rest transforms
are joint-local. See the official [UsdSkel schema documentation](https://openusd.org/dev/api/_usd_skel__schemas.html)
and [schema example](https://openusd.org/dev/api/_usd_skel__schema_overview.html).

The pinned legacy converter constructed the correct slash-delimited names, then
passed each complete path through `Tf.MakeValidIdentifier`. That sanitized the
slashes into underscores. The old files therefore contained 65 syntactically
valid root tokens per skinner, for example
`root_64_pelvis_63_spine_01_52`, instead of the intended path
`root_64/pelvis_63/spine_01_52`. `usdchecker` accepted that valid-but-wrong
topology, while SceneKit imported every one of the 65 bones as a sibling. The
converter also emitted an unused second animated Xform graph with 65 nodes.
Together these provide a concrete explanation for the observed deformation and
duplicate global animation resource.

`Scripts/repair_replayxi_legacy_usdz.py` is a deliberately narrow migration
tool for the two already-built fixtures. It accepts only the locked model SHA,
derives the exact hierarchy from that GLB, refuses any USD joint order other
than the known flattened converter output, namespaces the three skeletons,
removes the redundant graph, then rebuilds and validates the USDZ:

```sh
python3 Scripts/repair_replayxi_legacy_usdz.py \
  /path/to/legacy.usdz \
  /path/to/replayxi-night-striker.glb \
  /tmp/repaired.usdz
```

This repair is not a general converter and must not be used to accept an
unrelated model. New builds should use the patched build script instead.

## Validation and runtime contract

The repaired source fixture is 4,593,132 bytes; the styled kit fixture is
4,833,314 bytes. The source's measured content remains 14,318 triangles, 8,213
vertices, three meshes/materials, seven embedded textures, and 65 joints per
skeleton (approximately 1.81 m tall). The converter currently creates three
skeletons for body, eyes and eyebrows. The conversion smoke test found three
valid skeleton/mesh bindings and a maximum sampled sprint transform delta of
`1.286518`; `usdchecker --arkit -t` returned `Success!` for both packages.

The dependency-free audit can run on a clean macOS/Xcode worker:

```sh
python3 Scripts/audit_replayxi_player_usdz.py \
  ReplayXITests/Fixtures/ThirdParty/Quaternius/ReplayXIPlayerSprint.usdz \
  ReplayXITests/Fixtures/Generated/ReplayXIPlayerKit.usdz

python3 -m unittest discover -s Scripts/tests -p 'test_*.py' -v
```

It verifies stored/uncompressed USDZ members, safe member paths, reproducible
timestamps, root-layer ordering, ARKit USD conformance, Y-up/metre metadata,
explicit matching Skeleton/SkelAnimation joint orders, parent-before-child
ordering, one hierarchical root per skeleton, unique skeleton namespaces and
the absence of the duplicate animated Xform graph. It deliberately does not
claim to replace a rendered deformation test.

As an importer-level structural check, SceneKit now reports one root for every
65-bone skinner and only three animated nodes. The rejected files reported 65
roots for every skinner, 68 animated nodes and 274 total nodes; the repaired
sprint reports three one-root skinners, three animated nodes and 209 total
nodes. The styled kit has eight skinners because its five authored shells reuse
the body skeleton.

`ReplayXITests/ImportedPlayerAssetTests.swift` and
`ReplayXITests/ReplayImportedAthleteProviderTests.swift` define the visionOS
RealityKit pilot gate, including loading, exact byte/hash admission, animation
playback, deterministic seeking, clone resource sharing, bounds, runtime kit
override targets and geometric number discovery:

```swift
let player = try Entity.load(contentsOf: assetURL)
let sprint = try #require(player.availableAnimations.last)
_ = player.playAnimation(
    sprint.repeat(),
    transitionDuration: 0,
    startsPaused: true
)
```

The repaired file no longer contains the redundant global Xform animation.
Code should still select a playable skinned resource defensively rather than
depending on a semantic name until a production DCC export authors a stable
clip contract.

## Performance boundary

This asset is not a safe drop-in replacement for a full-pitch player
marker because it has no dedicated LOD and retains three skeleton copies. Its
seven PNGs decode to 21,495,808 bytes (20.5 MiB) at their base levels, or about
28.7 MB / 27.3 MiB with a full mip chain before other runtime overhead. A
production near-field model should use one shared skeleton, a texture atlas with
explicit budgets and authored near/mid/far LODs. Load once and clone/share where
RealityKit permits, while procedural markers remain available for distant and
full-pitch views. Profile 22 simultaneously animated instances on physical
Vision Pro hardware before enabling a full match. The development provider
therefore admits at most one imported near-field slot and seeks paused animation
controllers explicitly; it never advances a frame-driven animation clock.
