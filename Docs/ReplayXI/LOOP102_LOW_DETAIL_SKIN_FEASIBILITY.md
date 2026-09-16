# Loop102 — licensed low-detail skin feasibility

Status: **offline candidate only**. No bundled asset, runtime provider, source
library, camera, animation contract, near contact data or live skin cap changed.
Native admission is the separate Loop109 task; no native result is claimed here.

## Outcome

The refined candidate keeps a readable face, hands, boots and articulated body
within the existing far geometry ceilings: **1,707 vertices / 2,129 triangles /
80 joints / two materials**. It is not FIFA-quality, a new motion-capture system,
or a measured headset-performance improvement. Eight matched Blender previews
cover four poses, not all movement or viewing angles.

### Source and rights

- Existing Microsoft Rocketbox `Sports_Male_02`, MIT licence, source commit
  `0943055db6ec570bcef9f2c8b41c9e5467c808f9`.
- Existing Replay XI neutral Home kit/skin0 and normal maps. No downloads,
  club/FIFA content or new third-party artwork.
- The MIT notice is retained beside each final derivative and inside the USDZ
  layer metadata. Original source and bundled hashes remain unchanged.

## Controlled reduction

Source library:
`.codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayers.blend`.
SHA256 `58bfaa3086b64f6d0ddfea251241c0cb0f83631455ffead079d6e7be2f85de01`.

`Scripts/blender/build_low_detail_player_candidate.py` appends a read-only source
collection in factory-startup background Blender, copies the two meshes, and
decimates them before their armature modifier in rest space. It preserves the
source skeleton/rest matrices exactly. Native poses are resolved by **source
bone name**, not Blender iteration order. No distinct surface is welded.

The first successful low candidate (`Candidate-02`, session38120) had
1,339 GLB vertices /1,628 triangles. Its shoulder spike and bright crotch seam
were visible in the run/pass previews. Read-only seam analysis found609 body
UV-split coincident groups; 470 source seam positions did not survive that
aggressive collapse. This was evidence for preserving those seams, not a claim
that every displaced vertex was a visible defect.

The one bounded refinement (`Candidate-03`, session23705) uses a 0.30 body /0.20
head ratio and pins 86 existing vertices at39 coincident shoulder/crotch positions.
Their positions, UVs and weights remain exact. The spike and bright seam are no
longer visible in the inspected run, cut and pass views. Some knee, finger and
surface detail is necessarily reduced. The protected source rest skeleton and
exact repeated-pose geometry remain unchanged.

| Section | Blender vertices | Exported vertices | Triangles | Max influences |
| --- | ---: | ---: | ---: | ---: |
| Body |1,290 |1,296 |1,504 |4 |
| Head |411 |411 |625 |4 |
| Total |1,701 |1,707 |2,129 |4 |

The six extra GLB vertices are attribute splits. The refined candidate fits the
1,800/2,500 far ceilings, but **does not meet** the initial1,400/1,800 stretch
target. No geometric jersey digits are included; adding them needs a new budget.

Decimation produced more than four weights on one body vertex and11 head
vertices. Keeping the strongest four discarded at most0.02199 body weight and
0.08189 head weight before renormalisation. Facial extremes therefore remain an
explicit untested risk, despite the acceptable four-pose previews.

### Pose evidence

Native attachment:
`/private/tmp/replayxi-low102-runtime-poses/6D4325A8-2903-43A5-8178-F9DDA828AB5C.json`,
from `testFootballRetargetPoseGallery()` in
`/private/tmp/replayxi-parallel88-95-full-02.xcresult`.
It supplies run, cut-right and pass-contact. Idle is separately labelled as
source idle clip frame0, not a native recording.

All eight source/candidate PNGs and full mesh statistics are in
`.codex-derived/ReplayXI-Low102-Candidate-03/`.

| Pose | Candidate sole min (mm) | Body surface p95 error (mm) | Body max error (mm) |
| --- | ---: | ---: | ---: |
| Source idle |5.837 |5.096 |10.995 |
| Native run |7.042 |6.199 |19.013 |
| Native cut-right |6.102 |6.008 |14.948 |
| Native pass-contact |7.307 |5.891 |20.957 |

Surface error is original-to-candidate nearest-triangle distance, not a
physiology threshold. Positive sole clearance in these four poses does **not**
validate the old sparse contact profile for this mesh.

## Canonical USDZ admission prototype

Final frozen folder: `.codex-derived/ReplayXI-Low102-Canonical-03/`.

- `ReplayXILow102Canonical.usdz`:1,263,724 bytes;
  SHA256 `cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac`.
- `native-admission-fixture.json`:
  SHA256 `9cd03e16888fe635bc1e4d417d48895da33dd98b7be7dbf744e262f1177dd5fd`.
- `report.json` and the MIT notice.

`export_low_detail_admission_reference.py` exports actual Blender weighted
vertices and rest bone matrices from the frozen refined library. The source
mesh and candidate are never saved by this evidence job.

`build_replayxi_low_detail_candidate_usdz.py` uses Blender's bundled Python /
OpenUSD26.3 and Apple's USD tools; no dependencies were installed. It preserves
the admitted **Skeleton, Idle, Run, BodyMaterial and HeadMaterial blocks exactly**,
then replaces only the two mesh arrays with checked canonical data.

Important conversion checks:

1. Map all80 glTF source names and their parents to the exact motion order.
   Source Blender/glTF iteration order is **not** the canonical motion order.
2. Candidate glTF points and inverse binds include the source root's16.436 mm
   lift. Remove it once from canonical geometry; runtime root lift stays external.
   A draft formula that multiplied the mesh world matrix a second time would
   double that lift; the inverse-bind/Blender checks rejected that assumption.
3. Match every exported vertex by position, UV and named weights. Equivalent
   coincident vertices may share a match only when their weights are also equal.
   All Blender vertices are represented; rest-point difference≤0.344µm and
   UV difference≤2.981e-8.
4. Blender5.2's glTF exporter drops weights≤0.0001. Six vertices lost such tiny
   influences. The prototype verifies the exporter’s exact filtering rule and
   restores the original candidate weights from the checked Blender reference;
   it does not loosen the weight or pose test. Final max sum error4.471e-8.
5. The root lift is applied once to the actual packaged OpenUSD `SkinPoints`
   result, then compared to the actual Blender-deformed vertex array.

Maximum weighted vertex difference is **2.266µm** across all four poses, below
the explicit8µm Float32 round-trip budget. That is a numerical conversion
check—not a visual-quality or biological threshold. Canonical USD bind matrices
are preserved even though the rounded Blender rest construction differs by up
to0.000138887 in a matrix component; weighted geometry parity is checked directly.

Apple `usdchecker --arkit -t`, the existing archive/hierarchy preflight and the
shared-skeleton skinning audit pass without errors/warnings. A second complete
packaging run produced the same USDZ hash. All four new scripts compile with
Blender's bundled Python. Native RealityKit admission is still separate.

Setup failures were contained to new derived folders: a temporary OpenUSD stage
lifetime caused a weak-layer crash and was fixed by retaining the stage; exact
weight comparison exposed the glTF filtering above; an over-strict one-to-one
vertex-ID check was replaced by checked attribute/weight equivalence. No source
asset was overwritten or a failed candidate admitted.

### Native fixture layout

Schema1 fixture contains `asset`, `coordinates`, `skeleton`, `parts` and `poses`.
`parts` has packaged positions/normals/UVs/triangles and four canonical joint
indices/weights per vertex. `poses` contains all80 local TRS arrays plus expected
weighted positions with its explicit external `groundOffset`.

Each `*MatricesColumnMajor` array has80 matrices, each16 numbers, compatible with
native column-vector SIMD matrices. These are the transposed convention of USD's
row-vector matrix storage. Geometry is metres, Y-up, +Z forward. No old near
contact data or native import assumptions are embedded in the fixture.

## Full-vertex contact candidate — derived only

Final folder: `.codex-derived/ReplayXI-Low102-FullContact-03/`.
`ReplayXILow102FullContactCandidate.json` is **schemaVersion2**, explicitly
`profileKind: full-low-mesh`, hash-bound to the canonical USDZ and original motion.

- 1,707 weighted vertices;2,823 positive influences; four max per vertex.
- 265,785 bytes; SHA256
  `76e9cfe574345931ca945495f41a0e2fe872a182d8db4f7e3078a8baa4acf7b1`.
- 80 exact-name inverse-bind matrices,16 column-major Float32-exact numbers each.
  Max cast error from packaged double matrices:5.246e-8.
- External `rootBaseLift`; no baked extra height. Padding0.006m is an explicit
  caller policy, not added to any point or parity result.
- Every canonical vertex retained; no sparse lower-body coverage assumption.

Full-profile floor minimum vs packaged full-mesh skinning differs by≤2.966e-9m
across four poses; vs actual Blender by≤5.555e-7m. All individual vertex heights
differ from packaged results by≤2.120e-7m. These are offline calculations using
Float32-quantised inverse binds and double arithmetic, **not native CPU timings**.

Canonical inverse bind vs rounded motion-rest inverse differs by0.000138766
with offline double composition, or0.000138760 after Float32 cast. A native
admission test must measure Swift's actual Float composition before selecting a
validation tolerance; do not demand false bit equality or discard inverse binds.

The existing near schema1 remains fixed at512 support vertices /256KiB payload
and5012 source vertices. This proposed low profile exceeds its byte limit by
3,641 bytes and must have a separate decoder/explicit limit if later approved
(e.g.≤1800 vertices,≤7200 influences,≤512KiB). It is currently rejected by the
shipping near decoder, as intended.

Full low support needs4.68× as many weighted influence transforms per query as
near's603. Precompute inverse-bind local points once; no mesh readback, JSON
decode or allocation per update. Query the final blended/impact pose and only
raise penetrations, preserving authored airborne height and rewind determinism.
All80 bone updates still remain; polygon count alone does not justify raising
the shipping4-skin /2-POV cap. Benchmark the proposed native profile first.

## Remaining gates

- Native canonical import, shared clone safety, exact seek/rewind and native
  inverse-bind/vertex-weight admission (Loop109).
- Native full-contact parity over walk/run/cut/ball actions, impact/recovery,
  airborne frames, view-scale changes and repeated seeks.
- Scoped optimised CPU costs including the new profile, then device rendering
  and LOD-switch checks. No Simulator/offline render is a headset FPS test.
- More poses and views, especially mouths/fingers and geometric jersey numbers.
- A separate, approved runtime low-variant/provider path. No automatic asset
  replacement or live-cap increase follows from this feasibility result.
