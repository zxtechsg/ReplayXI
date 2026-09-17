# Loop122 — remove duplicate far-head package textures

## Result and scope

The derived far-head package drops from **540,760 to 21,563 bytes**: 519,197 bytes (96.01%) smaller. Its discarded imported material no longer embeds the 518,743-byte colour/normal PNG payload. Runtime-ready skin palettes remain owned by the existing head provider.

This is a package-size result, not a measured memory or cold-load improvement. No bundled asset or app/provider change was made during this candidate task.

## Reproducible candidate

- Script: `Scripts/build_replayxi_far_head_mesh_only_candidate.py`.
- Source: `.codex-derived/ReplayXI-Far114-Head-02/ReplayXIFar114Head.usdz`; SHA-256 `0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce`.
- Candidate: `.codex-derived/ReplayXI-Far122-MeshOnly-01/ReplayXIFar122Head.usdz`; SHA-256 `30b5213f5967da5fa2574f39dfe942b989fe94629994cd10ad7a739c45e32b3f`.
- A second build in `ReplayXI-Far122-MeshOnly-02` produced identical package bytes.
- The entire authored Face prim matches exactly: points, normals, UVs, triangles, bounds, metadata and material binding. Root/stage metadata and transforms match exactly; MIT notice retained.
- Unchanged 486 vertices, 749 triangles, one mesh, one PBR material, no bones. The material keeps its path, Preview Surface type, metallic 0 and roughness 0.73, but is neutral white with no texture inputs.
- The packaged candidate contains one stage, no PNGs or remaining asset-valued properties. All shipping player-resource hashes stayed unchanged.
- Script syntax and existing/outside-output-directory refusal checks pass. `usdchecker --arkit -t` succeeds with the same Xform registration warning present on the frozen source; not a warning-free claim.

## Native admission and image parity

`ReplayFarHeadMeshOnlyAdmissionTests` compares the exact hash-pinned packages. Initial receipt: **3/3 passed**, `/private/tmp/replayxi-far122-native-parity-01.xcresult`.

Native positions, normals, UVs, triangle indices, transforms, instance mapping and bounds match exactly. Both imports have **486 tangents and 486 bitangents**, also exactly equal. Both remain one-model/one-part/static PBR assets; only the candidate's initial colour/normal textures are absent. Imported roughness and metallic values match.

The test then gives both meshes the **same prepared runtime palette**, without changing pose, camera or light. Native calibration resolves Display P3, top-first rows, maximum channel error 1. At 512×512, every paired frame has **0 changed channels out of 1,048,576**; no image-difference tolerance was introduced.

| Paired view | Authored time | Palette / player | Foreground pixels |
| --- | ---: | --- | ---: |
| Keeper 0 | 26.46 s | 0 | 36,344 |
| Keeper 1 | 26.59 s | 4 | 35,939 |
| Standing | 10 s | 0 | 40,314 |
| Running head | 12.1 s | 4 | 39,580 |
| Running body | 11.6916667 s | navy-rb | 12,322 |
| Running body | 14.0833333 s | red-lw | 13,623 |

Evidence: `/private/tmp/replayxi-far122-native-parity-exports-01/`, including 12 PNGs, six image-parity JSONs, native import data and calibration. All six candidate views were inspected; their paired source frames are numerically identical. The simplified head facets, rigid far limbs and existing collar fit remain unchanged. This is not a quality upgrade or headset readability claim.

## Stronger isolated rerun

After the initial pass, the body-only nonempty guard was aligned with the existing Loop116 control: >2,000 foreground pixels and <50% frame area. The established head guard (>1,000, <70%) and strict zero-channel parity remain unchanged. Explicit far-body palette reset/prewarm and four actual limb-texture assertions remove reliance on prior test/cache state. Neither package nor the app was changed for the rerun.

Final focused receipt: **3/3 passed**, `/private/tmp/replayxi-far122-native-parity-02.xcresult`. Export: `/private/tmp/replayxi-far122-native-parity-exports-02/`. All six paired images retain zero changed channels; foreground counts and exact native attributes match the table and initial receipt above. Both complete source/candidate running-body pairs were inspected with the explicitly prepared limb palettes. Neck/collar placement and face/kit shading match, with no new visible defect.

- Final native import: `875A2EBE-E30A-4FC8-B26E-8E6B79AB4AD5.json`.
- Final navy-rb source/candidate: `AE88B8C6-2DFA-493A-8C4F-FCC702490793.png` / `AD36BCA9-8033-41BD-8B3E-463730C1F30E.png`.
- Final red-lw source/candidate: `257F6323-2152-4C10-9F6B-C4FA214D160C.png` / `94A27D62-6547-4C4A-ACD6-90A93BF536D2.png`.

## Bundled adoption

After both focused gates passed, root copied the exact 21,563-byte candidate to
`ReplayXI/Resources/Players/ReplayXIFarAthleteHead.usdz` and updated only the
provider's expected size/hash and neutral-material checks. The provider now
also rejects unexpected embedded base-colour or normal textures. Shared runtime
materials, geometry, head placement, motion and budgets are unchanged.

Integrated targeted receipt:
`/private/tmp/replayxi-far122-integrated-target-01.xcresult` — all 15 tests passed:
the eight existing provider/pose cases, three exact package-parity cases,
three full-scene work diagnostics and the whole-scene render audit. Final
integrated suite: 920 passed, one optional skip, zero failures; unsigned device
Release passed. See the [final batch receipt](VERIFIED_BATCH_122_124_2026-09-17.md).

Root also reproduced the package independently in
`.codex-derived/ReplayXI-Far122-MeshOnly-RootAudit-03/`: identical bytes/hash and
Face prim specification, with protected shipping resource hashes unchanged.

## Limits

This covers six fixed native offscreen poses, not every pose, GPU or headset. Package size alone establishes no peak-memory, setup-time or FPS benefit. The integrated app gate is separate from the original derived-only candidate checks.
