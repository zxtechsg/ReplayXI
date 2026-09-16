# Loop 96 — Far-player kit, skin and boot colour separation

## Scope

The existing distant player uses seven models with 399 vertices and 574 triangles. Its integrated legs were entirely sock-coloured and its integrated arms entirely shirt-coloured. This made exposed skin and boots hard to distinguish in the native-mesh audit. This batch changes colour placement only: no new geometry, source assets, joint motion, trajectory, camera, floor-support data or save schema.

The approved design uses two original **1 × 64** colour strips per palette. Leg rows separate shorts, exposed skin, socks and boots; outfield arm rows separate sleeve and skin. Keeper arms retain the long sleeve and use the existing kit trim colour at the hand. These are colour cues on the old silhouettes, not newly modelled gloves or anatomy.

## Implementation

- Only far `wholeLeg` and `wholeArm` meshes receive height-based UVs. U is 0.5; V addresses top-to-bottom native image rows with half-texel edge insets.
- Each limb still has one material slot. Both legs share a texture, as do both arms. No mesh split or extra draw model is introduced.
- Separate one-column textures avoid the arm/leg colour mixing that a shared two-limb atlas would introduce in its coarsest mips. Each strip has a complete seven-level mip chain and explicit linear/clamp sampling. Vertical colour averaging at extreme minification remains expected.
- Palette creation happens during prewarm or rig setup, never from the pose update. The cache holds at most 32 palette entries / 64 retained textures; failed preparations reserve a slot and are not retried. Invalid colours are rejected safely. A failed or full cache retains the previous flat limb materials.
- The original near/mid geometry and limb materials are untouched. Motion and the far floor guard are unchanged.

This is original generated colour data. No downloaded, licensed-source or contact-surface asset is rewritten.

## Test-first evidence

The baseline run `/private/tmp/replayxi-parallel96-99-prefx-02.xcresult` records two failing admission cases: 12 missing limb textures and 12 missing UV sets across the home, away and keeper fixtures. Geometry, near/mid and deterministic-seek controls pass.

Native baseline mesh positions, normals and triangle indices share SHA-256 `3f40c68f717193de03dc4c967382060a8686857bca2db62624ecc0a01bcce13d` for all three fixtures. Baseline export: `/private/tmp/replayxi-far96-geometry-before-01/79DE3E6A-62E0-429F-B67A-BCF68BA8A6B5.json`.

An initial post-fix build found a missing explicit UIKit import for `.white`; this was corrected before tests ran. The texture creation call was also updated to the non-deprecated `TextureResource(image:options:)` initializer without changing options.

## Verification and limits

The original five native post-fix cases pass in `/private/tmp/replayxi-parallel96-99-postfx-02.xcresult`: UV/texture admission, geometry, near/mid preservation and exact reverse seek. Four extra tests cover the success/failure cache bounds, cache sharing, malformed inputs, and zero new textures through 15 actual scene view/seek updates plus a second root. The captured pre-palette geometry digest is now an explicit regression assertion.

The expanded native run `/private/tmp/replayxi-parallel96-99-100-pre-02.xcresult` passes eight of nine cases. Its one failure is a test comparison-space mismatch: `SimpleMaterial` stores a colour-managed linear-P3 tint, but the fallback assertion compared it directly with source sRGB `UIColor`. The test now compares exact native tint against a fresh material created by the unchanged old flat-colour path. Texture-nil, geometry and floor-cache checks remain. A test-only ambiguous negative floating-point literal was also made explicitly `Float` before this run; no production logic or acceptance limits changed.

The separate Loop99 test-only helper reads the resource actually attached to the material. Its first known-colour controls detected native sRGB-to-Display-P3 conversion and linear readback; this is an audit colour-space issue, not evidence of a production palette failure. All six corrected readback/gamut/guard controls pass in the expanded bundle. The tenth palette test reads the actual attached leg/arm resources and checks seven representative rows per player against independently colour-converted source values (one 8-bit code value), including keeper sleeves/hands. Intended palette bytes are not substituted for native texture data.

**All 10 palette tests pass** in `/private/tmp/replayxi-parallel96-101-target-01.xcresult`, including the exact old-flat fallback comparison and native band checks. All eight Loop99 controls also pass (six texture and two linear-tint controls). The updated actual-mesh export is `/private/tmp/replayxi-far96-native-textures-02/40F4CF94-D386-49E6-A2BF-017A0ECBA872.json`; it carries colour-managed native P3 texture bytes and explicit canonical linear-Rec.709 material tints for Blender.

Final full native receipt: `/private/tmp/replayxi-parallel96-101-full-01.xcresult`, **837 passed, 1 optional skip, 0 failed (838 total)**. This includes the palette tests and the controlled-flat native export. Unsigned physical-device Release succeeds in `/private/tmp/replayxi-parallel96-101-release-01.log`.

The passing lifecycle attachment records **12 palettes / 24 texture creations** for this 22-player demo. The 15 view/seek updates, repeated prewarm and second root add **zero** palette preparations or texture creations. Evidence: `/private/tmp/replayxi-far96-cache-after-01/109A003D-3885-4144-AF3B-38CD8D859D6E.json`. The separate cap fixture passes at 32 cached palettes / 64 textures and uses flat fallback for later distinct palettes. These are setup/resource counts, not GPU timings or memory-allocation measurements.

## Current render inspection

The corrected `navy-rb` and `red-lw` images in `.codex-derived/ReplayXI-Far96-native-textures-02/` show clear sleeve/arm, shorts/thigh, sock and boot regions. No band inversion or wrapping seam is visible in those two views. Their report retains 399 vertices / 574 triangles and four textured limb models; corrected mesh minima are −0.119 μm and +0.179 μm. The faceless head and rigid far-limb silhouette are unchanged.

The controlled old-flat export is `/private/tmp/replayxi-far96-flat-native-01/5F03ECE6-E21E-480D-A26E-F8D4191182C0.json`; its matching renders are in `.codex-derived/ReplayXI-Far96-flat-native-01/`. It uses the tested failure/fallback seam, identical pose/geometry/light and the same corrected colour handling. UVs are still present but inert without a texture. Both corrected home and away before/after pairs were inspected: the old flat limbs have continuous shirt/sock colour, while the new strips visibly separate exposed skin, socks and dark boots. Geometry and the simple head remain unchanged. The older Loop94 PNGs are not used as the controlled colour baseline.

The source, ten tests and this note are frozen for the parent's scoped backup. Separate Loop102 model feasibility work is not part of this verified change.

This is a distant-avatar readability improvement, not FIFA-grade anatomy, a new running rig, a hardware performance result, or final Vision Pro shading/comfort QA. The seven-model budget is a scene/resource assertion, not a measured GPU draw-call count.
