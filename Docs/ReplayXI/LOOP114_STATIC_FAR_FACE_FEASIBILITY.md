# Loop114 — lightweight static far face

Status: **derived candidate and test-only admission**. This task does not bundle
or activate the head, change a rig, or raise the live skinned-player cap.

## Outcome

The candidate adds a readable face without an extra skeleton: **486 vertices,
749 triangles, one mesh and one material**. It reuses the admitted static
head's material and unchanged colour/normal textures. Reduced facial detail and
crown facets remain visible in close-ups; this is a far-face candidate, not a
replacement for the detailed near head.

Source: existing Microsoft Rocketbox MIT derivative
`ReplayXI/Resources/Players/ReplayXIAthleteHead.usdz`.
SHA256 `7446de58f31366aacf733060a12748b62c3dfb75a46994ba3ed32576355c1f20`.
No downloads, club/FIFA assets or new third-party artwork. The existing MIT
notice is retained beside the derivative; the source USD material/metadata is
preserved. All bundled player-resource hashes match before/after this job.

## Controlled reduction

`Scripts/blender/build_static_far_head_candidate.py` runs only in
factory-startup background Blender and requires a new `.codex-derived` folder.
It reads the source's Y-up local geometry and UVs directly, reduces a separate
copy, and replaces only the mesh arrays in a copy of the USD layer. It checks
the original material block, texture bytes, bounds, unit normals, mesh/material
counts and absence of skeletons. No distinct surfaces are welded.

The first candidate (`ReplayXI-Far114-Head-01`, Blender session64253) had
409 vertices/625 triangles. Its unprotected, coincident scalp UV seam collapsed
independently and left a visible slit. That candidate is **rejected**.

The bounded refinement (`ReplayXI-Far114-Head-02`, session92902) protects all
28 scalp-seam vertices, the lower neck and orientation extrema: 66 protected
vertices in total, with exact retained positions and UVs. At a0.24 collapse
ratio, the candidate has486 vertices/749 triangles. The slit is no longer
visible in the four inspected orientations. Nose, lip and cheek detail is
lower, and the crown is more angular.

| Metric | Source | Candidate |
| --- | ---: | ---: |
| Vertices |1,724 |486 |
| Triangles |3,128 |749 |
| Meshes/materials |1/1 |1/1 |
| Bones |0 |0 |
| USDZ bytes |— |540,760 |

X/Y extrema and minimum Z are unchanged; maximum Z differs by0.107326 mm.
Source-to-candidate nearest-surface distance is1.549 mm at p95,6.576 mm maximum.
The reverse comparison is1.404 mm at p95,2.669 mm maximum. These are geometric
measurements, not visual-quality or physiological thresholds.

Final frozen files are in `.codex-derived/ReplayXI-Far114-Head-02/`:

- `ReplayXIFar114Head.usdz`:
  `0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce`.
- `native-admission-fixture.json`:
  `bb859f9304eb2c089a1643e9ff28e68244b02e50f407ca751af29916d01a946b`.
- `report.json`:
  `d29af3c7e32dd9c15149c6c6487a79e5156e6ce284370de99c6b5a0bb09d15d6`.
- Eight matched Blender PNGs and the MIT notice.

`usdchecker --arkit -t` exits0 and reports `Success!`. It also emits a
Connectable-behaviour registration warning for `Xform`; the unchanged admitted
source emits the same warning. This is not a warning-free validation claim.

## Placement and pose evidence

The existing textured-head contract is local Y0.125 m with mesh X scale1.07.
The old far ellipsoid's Y0.170 m placement is **not interchangeable**. The
candidate preserves the textured source's geometry origin, orientation and UV
layout. Existing five skin palettes can share this layout; actual runtime
texture sharing and cache behaviour are not tested by this offline candidate.

Frozen native Loop80 pose attachment:
`/private/tmp/replayxi-window80-after-01/63C43612-0281-4DD4-8E47-C5C280E827AB.json`.
SHA256 `5e1b700b790bda11c496146d7088390aba44ffafad7fa50822f9a374fbd2785f`.

Four exact procedural head/neck composites are used: keeper26.46 s and26.59 s,
standing10 s, running12.1 s. Only actor heading is removed, identically for
source/candidate, to make the body-relative crop readable. The rotated neck
offset, head orientation and1.07 X scale are preserved. All eight Blender
source/candidate images were inspected. These are head/neck crops, not a full
far-body collar or LOD-transition test.

## Native test boundary

`ReplayXITests/ReplayStaticFarHeadAdmissionTests.swift` is test-only. It pins
USDZ, geometry fixture, report and original-source identities. A genuinely
absent optional derived USDZ may skip; a present corrupt or changed fixture
must fail.

The admission test checks the actual imported positions, normals, UVs,
triangles, bounds, material/texture counts, no skeleton/skin weights, shared
clone mesh and exact repeated/reversed placement. A separate renderer test
first calibrates native colour gamut and row order using known swatches, then
captures all four source/candidate pairs with identical lights, camera and
head-root placement. It rejects empty/clipped previews and exports colour-
profiled PNGs only after calibration succeeds.

Native receipt: all three tests pass in
`/private/tmp/replayxi-parallel102-114-full-01.xcresult`. The whole batch has
883 tests:881 passed, one optional skip and one unrelated root-owned fixture
failure. That fixture was corrected and its seven-case targeted rerun passed;
a clean full rerun is tracked separately by the parent. The three static-head
results do not depend on that correction.

Eight native source/candidate PNGs and frame reports are exported to
`/private/tmp/replayxi-head114-native-01/`; its manifest maps generated filenames
to poses. Calibration is **Display P3, top-first rows, maximum channel error1**.
The source/candidate foreground pixels are36,412/36,331 for keeper26.46 s,
36,036/35,955 for keeper26.59 s,40,208/40,306 standing, and39,599/39,592 running.
All frames are nonempty and fully within the image. All eight were inspected:
no scalp slit or clipping is visible, and neck placement matches the source.
Reduced lips, nose and ear shape and faceted cheeks remain apparent, especially
in the standing profile. This supports simplified far-distance use, not near
facial fidelity. Source parse and whitespace checks also pass.

## Remaining limits

- Static rigid head only; no facial animation or additional skeletal work.
- Replacing the current far head would estimate820 vertices/1,225 triangles
  across the same seven model entities, based on the current399/574 body minus
  its65/98 head plus this candidate. That is a source-derived budget estimate,
  not an integrated native draw/geometry measurement.
- Full-body collar, all five skin tones, LOD switching and actual scene scale
  need separate integration checks before activation.
- No hardware FPS, renderer-cost improvement or final headset QA is claimed.
